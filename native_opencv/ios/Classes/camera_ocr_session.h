// Pure-NDK Camera2 capture + OCR pipeline for Android. Replaces the Flutter
// `camera` plugin.
//
// Two simultaneous Camera2 outputs (the same design the `camera` package uses):
//   1. The Flutter preview Surface — the camera renders straight into it on the
//      GPU path, zero CPU copy, full framerate. Orientation is corrected by a
//      RotatedBox on the Dart side (the preview is delivered sensor-landscape).
//   2. An AImageReader (YUV_420_888) consumed ONLY by the OCR worker, throttled
//      (every Nth frame, drop-when-busy). The worker converts to BGR, rotates
//      upright, runs DdrocrInstance::process_image, and pushes the result to
//      Dart via the FFI NativeCallable.
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
    // The preview window is supplied later (Java SurfaceProducer), via
    // setPreviewWindow, since its size depends on the camera sizes this picks.
    CameraOcrSession(const std::string &dataPath, const COCRConfig &config);
    ~CameraOcrSession();

    // Registers the FFI result sink (NativeCallable from Dart). Invoked by the
    // OCR worker once per processed frame; Dart owns/frees the CCameraResult.
    void setResultFn(CameraResultFn fn) { resultFn_ = fn; }

    // Chosen preview output size, in sensor (landscape) orientation. Java sets
    // the SurfaceProducer to this; Dart applies the rotation for display.
    int previewWidth() const { return previewWidth_; }
    int previewHeight() const { return previewHeight_; }
    // Sensor mounting rotation (0/90/180/270); Dart turns this into the
    // RotatedBox quarter-turns for the preview + ROI overlay.
    int sensorOrientation() const { return sensorOrientation_; }

    // Preview Surface lifecycle (driven by the Java SurfaceProducer callback).
    // setPreviewWindow takes ownership of an ANativeWindow ref. If the camera is
    // already running it rebuilds the session to include the new surface.
    void setPreviewWindow(ANativeWindow *window);
    void onPreviewSurfaceLost();

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

    std::string dataPath_;
    ANativeWindow *previewWindow_ = nullptr;
    CameraResultFn resultFn_ = nullptr;

    DdrocrInstance *instance_ = nullptr;

    ACameraManager *manager_ = nullptr;
    std::string cameraId_;
    int sensorOrientation_ = 90;
    int analysisWidth_ = 0;   // landscape (sensor) dims, full-res YUV for OCR
    int analysisHeight_ = 0;
    int previewWidth_ = 0;    // landscape preview output size
    int previewHeight_ = 0;

    ACameraDevice *device_ = nullptr;
    AImageReader *reader_ = nullptr;
    ANativeWindow *readerWindow_ = nullptr;
    ACaptureSessionOutputContainer *outputs_ = nullptr;
    ACaptureSessionOutput *readerOutput_ = nullptr;
    ACameraOutputTarget *readerTarget_ = nullptr;
    ACaptureSessionOutput *previewOutput_ = nullptr;
    ACameraOutputTarget *previewTarget_ = nullptr;
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
    // Cap the preview output's longer edge. "PRIV preview + YUV maximum" is a
    // guaranteed Camera2 stream combination on LIMITED+ devices when preview is
    // <= 1080p, so keep the preview within that bound.
    static constexpr int kPreviewMaxLongEdge = 1920;
};

#endif // __ANDROID__
