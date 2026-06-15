// Pure-NDK Camera2 capture + OCR pipeline for Android. Replaces the Flutter
// `camera` plugin's per-frame YUV → Dart → FFI round trip: an AImageReader
// feeds full-resolution YUV_420_888 frames straight into the existing C++
// DdrocrInstance::process_image, and the rotated BGR frame the OCR consumes is
// also down-scaled and blitted into the Flutter preview SurfaceTexture (so the
// preview and the ROI overlay share one pixel space, upright).
#pragma once

// Android-only (NDK Camera2). Guarded so the iOS build, which globs every
// header/source under Classes/, never tries to parse the NDK includes below.
#ifdef __ANDROID__

#include <android/native_window.h>
#include <camera/NdkCameraDevice.h>
#include <camera/NdkCameraManager.h>
#include <media/NdkImageReader.h>

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "ddrocr_instance.h"
#include "camera_result.h"

class CameraOcrSession {
public:
    CameraOcrSession(const std::string &dataPath, const COCRConfig &config,
                     ANativeWindow *previewWindow);
    ~CameraOcrSession();

    // Registers the FFI result sink (NativeCallable from Dart). Invoked by the
    // OCR worker once per processed frame; Dart owns/frees the CCameraResult.
    void setResultFn(CameraResultFn fn) { resultFn_ = fn; }

    // Preview surface dimensions (portrait, matching the rotated OCR frame).
    int previewWidth() const { return previewWidth_; }
    int previewHeight() const { return previewHeight_; }

    // Opens the camera device + session and begins the repeating request.
    // Returns false if the camera could not be opened (caller should surface a
    // FlutterError). Camera permission must already be granted.
    bool start(bool debug);
    // Stops the repeating request and releases the camera device/session.
    void stop();

    void setDebug(bool debug) { debug_ = debug; }

private:
    // Camera2 lifecycle
    bool openCameraLocked();
    void closeCameraLocked();
    bool pickBackCameraAndSizes();

    // AImageReader callback (static trampoline + member impl)
    static void onImageAvailable(void *ctx, AImageReader *reader);
    void handleImage(AImageReader *reader);

    // OCR worker thread
    void workerLoop();
    void blitPreview(const cv::Mat &bgrRotated);

    std::string dataPath_;
    ANativeWindow *previewWindow_ = nullptr;
    CameraResultFn resultFn_ = nullptr;

    DdrocrInstance *instance_ = nullptr;

    ACameraManager *manager_ = nullptr;
    std::string cameraId_;
    int sensorOrientation_ = 90;
    int analysisWidth_ = 0;   // landscape (sensor) dims
    int analysisHeight_ = 0;
    int previewWidth_ = 0;    // portrait (rotated) preview dims
    int previewHeight_ = 0;

    ACameraDevice *device_ = nullptr;
    AImageReader *reader_ = nullptr;
    ANativeWindow *readerWindow_ = nullptr;
    ACaptureSessionOutputContainer *outputs_ = nullptr;
    ACaptureSessionOutput *readerOutput_ = nullptr;
    ACameraOutputTarget *readerTarget_ = nullptr;
    ACaptureRequest *request_ = nullptr;
    ACameraCaptureSession *session_ = nullptr;

    // Capture-session/device callback structs (kept alive while open).
    ACameraDevice_StateCallbacks deviceCallbacks_{};
    ACameraCaptureSession_stateCallbacks sessionCallbacks_{};
    AImageReader_ImageListener imageListener_{};

    std::mutex cameraMutex_;

    // Frame hand-off: listener thread fills queuedFrame_, worker consumes it.
    std::mutex frameMutex_;
    std::condition_variable frameCv_;
    std::vector<uint8_t> queuedNv21_; // packed NV21 (Y then interleaved VU)
    bool frameReady_ = false;
    bool workerRunning_ = false;
    std::thread worker_;

    std::atomic<bool> busy_{false};
    std::atomic<bool> running_{false};
    std::atomic<bool> debug_{false};
    int frameCounter_ = 0;
    static constexpr int kFrameThreshold = 3;
    static constexpr int kPreviewMaxWidth = 720;
};

#endif // __ANDROID__
