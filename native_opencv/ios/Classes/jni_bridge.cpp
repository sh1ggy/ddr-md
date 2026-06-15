// JNI shim between the Java plugin (NativeOpencvPlugin) and the pure-NDK
// CameraOcrSession. Keeps Java thin: it owns the Flutter SurfaceTexture, the
// channels, and permissions; everything camera/OCR lives in C++.
//
// Android-only translation unit: lives in ios/Classes/ with the shared sources
// but is guarded out of the iOS build (the podspec globs every .cpp here).
#ifdef __ANDROID__

#include <jni.h>
#include <android/log.h>
#include <android/native_window_jni.h>

#include <string>

#include "camera_ocr_session.h"
#include "config_marshal.h"

#define LOG_TAG "ddr-cam-jni"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

JavaVM *gJvm = nullptr;

// Holds the session plus the JNI handles needed to deliver results back to the
// Java plugin instance.
struct SessionBundle {
    CameraOcrSession *session = nullptr;
    jobject pluginRef = nullptr; // global ref to the NativeOpencvPlugin instance
    jmethodID onResult = nullptr;
};

// Attaches the (worker) thread to the JVM for the duration of a call.
struct ScopedEnv {
    JNIEnv *env = nullptr;
    bool attached = false;
    ScopedEnv() {
        if (gJvm->GetEnv((void **)&env, JNI_VERSION_1_6) == JNI_EDETACHED) {
            if (gJvm->AttachCurrentThread(&env, nullptr) == JNI_OK) attached = true;
        }
    }
    ~ScopedEnv() {
        if (attached) gJvm->DetachCurrentThread();
    }
};

jbyteArray toByteArray(JNIEnv *env, const std::vector<uint8_t> &v) {
    if (v.empty()) return nullptr;
    jbyteArray arr = env->NewByteArray((jsize)v.size());
    env->SetByteArrayRegion(arr, 0, (jsize)v.size(),
                            reinterpret_cast<const jbyte *>(v.data()));
    return arr;
}

void deliverResult(SessionBundle *bundle, const OcrFrameResult &r) {
    ScopedEnv scoped;
    JNIEnv *env = scoped.env;
    if (!env) return;

    jintArray rois = env->NewIntArray((jsize)r.rois.size());
    if (!r.rois.empty()) {
        env->SetIntArrayRegion(rois, 0, (jsize)r.rois.size(), r.rois.data());
    }

    jclass strClass = env->FindClass("java/lang/String");
    jobjectArray ocr = env->NewObjectArray((jsize)r.ocr.size(), strClass, nullptr);
    for (jsize i = 0; i < (jsize)r.ocr.size(); i++) {
        jstring s = env->NewStringUTF(r.ocr[i].c_str());
        env->SetObjectArrayElement(ocr, i, s);
        env->DeleteLocalRef(s);
    }

    jbyteArray mask = toByteArray(env, r.maskPng);
    jbyteArray crop = toByteArray(env, r.cropPng);
    jbyteArray capture = toByteArray(env, r.captureJpg);

    env->CallVoidMethod(bundle->pluginRef, bundle->onResult,
                        (jboolean)r.isDetected, (jint)r.detailsRoiIndex,
                        (jint)r.width, (jint)r.height, rois, ocr, mask, crop,
                        capture);

    env->DeleteLocalRef(rois);
    env->DeleteLocalRef(ocr);
    env->DeleteLocalRef(strClass);
    if (mask) env->DeleteLocalRef(mask);
    if (crop) env->DeleteLocalRef(crop);
    if (capture) env->DeleteLocalRef(capture);
}

} // namespace

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *) {
    gJvm = vm;
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_example_native_1opencv_NativeOpencvPlugin_nativeInit(
    JNIEnv *env, jobject thiz, jobject surface, jstring dataPath,
    jintArray cfgInts, jdoubleArray cfgDoubles) {
    ANativeWindow *window =
        surface ? ANativeWindow_fromSurface(env, surface) : nullptr;

    const char *pathChars = env->GetStringUTFChars(dataPath, nullptr);
    std::string path(pathChars ? pathChars : "");
    env->ReleaseStringUTFChars(dataPath, pathChars);

    // Build the OCR config from the Dart calibration arrays (lib/ocr_config.dart).
    COCRConfig config;
    {
        jint *ints = cfgInts ? env->GetIntArrayElements(cfgInts, nullptr) : nullptr;
        jdouble *doubles =
            cfgDoubles ? env->GetDoubleArrayElements(cfgDoubles, nullptr) : nullptr;
        jsize ni = cfgInts ? env->GetArrayLength(cfgInts) : 0;
        jsize nd = cfgDoubles ? env->GetArrayLength(cfgDoubles) : 0;
        config = BuildCOCRConfigFromArrays(reinterpret_cast<const int32_t *>(ints),
                                           (int)ni, doubles, (int)nd);
        if (ints) env->ReleaseIntArrayElements(cfgInts, ints, JNI_ABORT);
        if (doubles) env->ReleaseDoubleArrayElements(cfgDoubles, doubles, JNI_ABORT);
    }

    auto *bundle = new SessionBundle();
    bundle->pluginRef = env->NewGlobalRef(thiz);
    jclass cls = env->GetObjectClass(thiz);
    bundle->onResult = env->GetMethodID(
        cls, "onNativeResult", "(ZIII[I[Ljava/lang/String;[B[B[B)V");
    env->DeleteLocalRef(cls);

    SessionBundle *bundlePtr = bundle;
    bundle->session = new CameraOcrSession(
        path, config, window, [bundlePtr](const OcrFrameResult &r) {
            deliverResult(bundlePtr, r);
        });

    jlong vals[3] = {
        reinterpret_cast<jlong>(bundle),
        bundle->session->previewWidth(),
        bundle->session->previewHeight(),
    };
    jlongArray out = env->NewLongArray(3);
    env->SetLongArrayRegion(out, 0, 3, vals);
    return out;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_native_1opencv_NativeOpencvPlugin_nativeStart(
    JNIEnv *, jobject, jlong handle, jboolean debug) {
    auto *bundle = reinterpret_cast<SessionBundle *>(handle);
    if (!bundle || !bundle->session) return JNI_FALSE;
    return bundle->session->start(debug) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_native_1opencv_NativeOpencvPlugin_nativeStop(
    JNIEnv *, jobject, jlong handle) {
    auto *bundle = reinterpret_cast<SessionBundle *>(handle);
    if (bundle && bundle->session) bundle->session->stop();
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_native_1opencv_NativeOpencvPlugin_nativeSetDebug(
    JNIEnv *, jobject, jlong handle, jboolean debug) {
    auto *bundle = reinterpret_cast<SessionBundle *>(handle);
    if (bundle && bundle->session) bundle->session->setDebug(debug);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_native_1opencv_NativeOpencvPlugin_nativeDispose(
    JNIEnv *env, jobject, jlong handle) {
    auto *bundle = reinterpret_cast<SessionBundle *>(handle);
    if (!bundle) return;
    // Deleting the session joins the OCR worker first, so no further callbacks
    // can run after this returns — safe to drop the JNI refs.
    delete bundle->session;
    if (bundle->pluginRef) env->DeleteGlobalRef(bundle->pluginRef);
    delete bundle;
}

#endif // __ANDROID__
