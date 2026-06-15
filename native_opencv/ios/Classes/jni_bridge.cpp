// Android glue for the native camera/OCR session.
//
// Split by interop kind, matching the rest of the app:
//   • JNI  — ONLY the unavoidable platform handoff: turn the Flutter
//            SurfaceTexture's Surface into an ANativeWindow and create/destroy
//            the C++ session. (Flutter's texture registry is Java-only.)
//   • FFI  — extern "C" camera_* entry points Dart calls directly (start/stop/
//            setDebug) plus the per-frame result delivery via a NativeCallable.
//            No JNI, no EventChannel in the result path.
//
// Android-only translation unit: lives in ios/Classes/ with the shared sources
// but is guarded out of the iOS build (the podspec globs every .cpp here).
#ifdef __ANDROID__

#include <jni.h>
#include <android/native_window_jni.h>

#include <string>

#include "camera_ocr_session.h"
#include "camera_result.h"
#include "config_marshal.h"

// ---- JNI: texture/Surface handoff + session lifecycle ----------------------

// Returns {sessionPtr, previewWidth, previewHeight}.
extern "C" JNIEXPORT jlongArray JNICALL
Java_com_example_native_1opencv_NativeOpencvPlugin_nativeCreateSession(
    JNIEnv *env, jobject /*thiz*/, jobject surface, jstring dataPath,
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

    auto *session = new CameraOcrSession(path, config, window);

    jlong vals[3] = {
        reinterpret_cast<jlong>(session),
        session->previewWidth(),
        session->previewHeight(),
    };
    jlongArray out = env->NewLongArray(3);
    env->SetLongArrayRegion(out, 0, 3, vals);
    return out;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_native_1opencv_NativeOpencvPlugin_nativeDestroySession(
    JNIEnv * /*env*/, jobject /*thiz*/, jlong handle) {
    auto *session = reinterpret_cast<CameraOcrSession *>(handle);
    // The destructor stops the camera and joins the OCR worker, so no FFI
    // callback can fire after this returns.
    delete session;
}

// ---- FFI: control + result delivery (Dart ↔ C++ directly) ------------------

// used + default visibility so Dart's dlsym finds them and the linker doesn't
// strip them (no compile-time callers).
#define FFI_EXPORT extern "C" __attribute__((visibility("default"))) __attribute__((used))

FFI_EXPORT void camera_register_callback(void *session, CameraResultFn cb) {
    if (session) static_cast<CameraOcrSession *>(session)->setResultFn(cb);
}

FFI_EXPORT int32_t camera_start(void *session, int32_t debug) {
    if (!session) return 0;
    return static_cast<CameraOcrSession *>(session)->start(debug != 0) ? 1 : 0;
}

FFI_EXPORT void camera_stop(void *session) {
    if (session) static_cast<CameraOcrSession *>(session)->stop();
}

FFI_EXPORT void camera_set_debug(void *session, int32_t enabled) {
    if (session) static_cast<CameraOcrSession *>(session)->setDebug(enabled != 0);
}

FFI_EXPORT void camera_free_result(void *result) {
    FreeCCameraResult(static_cast<CCameraResult *>(result));
}

#endif // __ANDROID__
