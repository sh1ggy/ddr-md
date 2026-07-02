// Android-only translation unit. This file lives alongside the shared sources
// in ios/Classes/ (so it's tracked with them), but the iOS podspec globs every
// .cpp here — the __ANDROID__ guard makes it compile to nothing on iOS.
#ifdef __ANDROID__

#include "camera_ocr_session.h"

#include <android/log.h>
#include <opencv2/opencv.hpp>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <vector>

#define LOG_TAG "ddr-cam"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

CameraOcrSession::CameraOcrSession(const std::string &dataPath,
                                   const COCRConfig &config) {
    dataPath_ = dataPath;
    // config comes from lib/ocr_config.dart via the JNI bridge — not the C++
    // struct defaults, which diverge from the Dart calibration.
    instance_ = new DdrocrInstance(dataPath_, config);

    manager_ = ACameraManager_create();
    if (!pickBackCameraAndSizes()) {
        LOGE("Failed to find a back camera / YUV size");
    }

    // Full-res YUV reader for OCR (the preview is a separate, direct camera
    // output — see openCameraLocked).
    if (analysisWidth_ > 0 && analysisHeight_ > 0) {
        AImageReader_new(analysisWidth_, analysisHeight_, AIMAGE_FORMAT_YUV_420_888,
                         /*maxImages*/ 4, &reader_);
        AImageReader_getWindow(reader_, &readerWindow_);
        imageListener_.context = this;
        imageListener_.onImageAvailable = &CameraOcrSession::onImageAvailable;
        AImageReader_setImageListener(reader_, &imageListener_);
    }

    // Start the two-stage OCR workers; they idle until frames/jobs are queued.
    workerRunning_ = true;
    detectorThread_ = std::thread(&CameraOcrSession::detectorLoop, this);
    consumerThread_ = std::thread(&CameraOcrSession::consumerLoop, this);
}

CameraOcrSession::~CameraOcrSession() {
    stop();

    {
        std::lock_guard<std::mutex> lk(frameMutex_);
        workerRunning_ = false;
        frameReady_ = true;
    }
    frameCv_.notify_all();
    jobCv_.notify_all();
    if (detectorThread_.joinable()) detectorThread_.join();
    if (consumerThread_.joinable()) consumerThread_.join();

    if (reader_) {
        AImageReader_delete(reader_); // also tears down readerWindow_
        reader_ = nullptr;
        readerWindow_ = nullptr;
    }
    if (manager_) {
        ACameraManager_delete(manager_);
        manager_ = nullptr;
    }
    if (previewWindow_) {
        ANativeWindow_release(previewWindow_);
        previewWindow_ = nullptr;
    }
    delete instance_;
    instance_ = nullptr;
}

bool CameraOcrSession::pickBackCameraAndSizes() {
    ACameraIdList *idList = nullptr;
    if (ACameraManager_getCameraIdList(manager_, &idList) != ACAMERA_OK) return false;

    bool found = false;
    for (int i = 0; i < idList->numCameras; i++) {
        const char *id = idList->cameraIds[i];
        ACameraMetadata *chars = nullptr;
        if (ACameraManager_getCameraCharacteristics(manager_, id, &chars) != ACAMERA_OK)
            continue;

        ACameraMetadata_const_entry facing{};
        if (ACameraMetadata_getConstEntry(chars, ACAMERA_LENS_FACING, &facing) == ACAMERA_OK &&
            facing.data.u8[0] == ACAMERA_LENS_FACING_BACK) {
            cameraId_ = id;

            ACameraMetadata_const_entry orient{};
            if (ACameraMetadata_getConstEntry(chars, ACAMERA_SENSOR_ORIENTATION, &orient) ==
                ACAMERA_OK) {
                sensorOrientation_ = orient.data.i32[0];
            }

            // Collect all YUV_420_888 output sizes.
            std::vector<std::pair<int, int>> sizes;
            ACameraMetadata_const_entry streams{};
            if (ACameraMetadata_getConstEntry(
                    chars, ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS, &streams) ==
                ACAMERA_OK) {
                for (uint32_t e = 0; e + 3 < streams.count; e += 4) {
                    int32_t format = streams.data.i32[e];
                    int32_t w = streams.data.i32[e + 1];
                    int32_t h = streams.data.i32[e + 2];
                    int32_t isInput = streams.data.i32[e + 3];
                    if (isInput) continue;
                    if (format != AIMAGE_FORMAT_YUV_420_888) continue;
                    sizes.emplace_back(w, h);
                }
            }

            // Analysis = largest YUV (the OCR ROI calibration assumes high res).
            int64_t bestArea = 0;
            for (auto &s : sizes) {
                int64_t a = (int64_t)s.first * s.second;
                if (a > bestArea) {
                    bestArea = a;
                    analysisWidth_ = s.first;
                    analysisHeight_ = s.second;
                }
            }

            // Preview = largest size with the SAME aspect ratio as analysis and
            // long edge <= cap (so "PRIV preview + YUV maximum" stays a
            // guaranteed stream combination, and so the preview and the OCR
            // frame share one field of view → the ROI overlay aligns).
            if (analysisWidth_ > 0) {
                int64_t prevArea = 0;
                for (auto &s : sizes) {
                    int longEdge = std::max(s.first, s.second);
                    if (longEdge > kPreviewMaxLongEdge) continue;
                    // aspect match: w1*h2 == w2*h1 (within rounding)
                    int64_t cross = (int64_t)s.first * analysisHeight_ -
                                    (int64_t)analysisWidth_ * s.second;
                    if (std::llabs(cross) >
                        (int64_t)analysisWidth_ * analysisHeight_ / 100) {
                        continue; // >1% off the analysis aspect
                    }
                    int64_t a = (int64_t)s.first * s.second;
                    if (a > prevArea) {
                        prevArea = a;
                        previewWidth_ = s.first;
                        previewHeight_ = s.second;
                    }
                }
                if (previewWidth_ == 0) { // nothing under the cap matched
                    previewWidth_ = analysisWidth_;
                    previewHeight_ = analysisHeight_;
                }
            }

            found = true;
            ACameraMetadata_free(chars);
            break;
        }
        ACameraMetadata_free(chars);
    }
    ACameraManager_deleteCameraIdList(idList);
    LOGI("camera %s orient=%d analysis=%dx%d preview=%dx%d", cameraId_.c_str(),
         sensorOrientation_, analysisWidth_, analysisHeight_, previewWidth_,
         previewHeight_);
    return found && analysisWidth_ > 0;
}

// ---- Preview surface lifecycle (Java SurfaceProducer callback) --------------

void CameraOcrSession::setPreviewWindow(ANativeWindow *window) {
    std::lock_guard<std::mutex> lk(cameraMutex_);
    if (previewWindow_ == window) return;
    if (previewWindow_) ANativeWindow_release(previewWindow_);
    previewWindow_ = window; // takes ownership of the fromSurface ref
    if (running_) {
        // Rebuild the session so the (new) preview surface becomes a target.
        if (session_) closeCameraLocked();
        if (!openCameraLocked()) {
            closeCameraLocked();
            running_ = false;
        }
    }
}

void CameraOcrSession::onPreviewSurfaceLost() {
    std::lock_guard<std::mutex> lk(cameraMutex_);
    ANativeWindow *old = previewWindow_;
    previewWindow_ = nullptr;
    if (running_) {
        // Tear down the session/device (the surface is invalid) but keep
        // running_ as the resume intent — setPreviewWindow rebuilds on return.
        closeCameraLocked();
    }
    if (old) ANativeWindow_release(old);
}

// ---- Camera open/close ------------------------------------------------------

bool CameraOcrSession::start(bool debug) {
    debug_ = debug;
    std::lock_guard<std::mutex> lk(cameraMutex_);
    if (running_ && session_) return true;
    // Pick up a details template written/updated after session creation (the
    // Dart side re-copies assets on every init, incl. hot restart, but this
    // session object outlives that).
    instance_->reloadDetailsTemplate();
    if (!reader_ || cameraId_.empty()) {
        LOGE("start() with no reader/camera");
        return false;
    }
    if (!openCameraLocked()) {
        closeCameraLocked();
        return false;
    }
    frameCounter_ = 0;
    busy_ = false;
    running_ = true;
    return true;
}

void CameraOcrSession::stop() {
    std::lock_guard<std::mutex> lk(cameraMutex_);
    running_ = false;
    closeCameraLocked();
    // Abandon queued OCR work: once the camera is closed the detector stops
    // pushing, so drop every job still on the LIFO stack rather than letting the
    // consumer grind through stale frames. The one job already in-flight on the
    // consumer finishes (recognise_details / OpenCV can't be interrupted).
    {
        std::lock_guard<std::mutex> jlk(jobMutex_);
        jobStack_.clear();
    }
}

bool CameraOcrSession::openCameraLocked() {
    deviceCallbacks_.context = this;
    deviceCallbacks_.onDisconnected = [](void *, ACameraDevice *) {
        LOGE("camera disconnected");
    };
    deviceCallbacks_.onError = [](void *, ACameraDevice *, int err) {
        LOGE("camera device error %d", err);
    };

    if (ACameraManager_openCamera(manager_, cameraId_.c_str(), &deviceCallbacks_,
                                  &device_) != ACAMERA_OK ||
        device_ == nullptr) {
        LOGE("openCamera failed");
        return false;
    }

    // The capture session is created synchronously; onActive/onReady/onClosed
    // are state notifications only (no onConfigured in the NDK struct).
    sessionCallbacks_.context = this;
    sessionCallbacks_.onActive = [](void *, ACameraCaptureSession *) {};
    sessionCallbacks_.onReady = [](void *, ACameraCaptureSession *) {};
    sessionCallbacks_.onClosed = [](void *, ACameraCaptureSession *) {};

    ACaptureSessionOutputContainer_create(&outputs_);
    ACaptureSessionOutput_create(readerWindow_, &readerOutput_);
    ACaptureSessionOutputContainer_add(outputs_, readerOutput_);
    if (previewWindow_) {
        ACaptureSessionOutput_create(previewWindow_, &previewOutput_);
        ACaptureSessionOutputContainer_add(outputs_, previewOutput_);
    }

    if (ACameraDevice_createCaptureSession(device_, outputs_, &sessionCallbacks_,
                                           &session_) != ACAMERA_OK) {
        LOGE("createCaptureSession failed");
        return false;
    }

    if (ACameraDevice_createCaptureRequest(device_, TEMPLATE_PREVIEW, &request_) !=
        ACAMERA_OK) {
        LOGE("createCaptureRequest failed");
        return false;
    }
    ACameraOutputTarget_create(readerWindow_, &readerTarget_);
    ACaptureRequest_addTarget(request_, readerTarget_);
    if (previewWindow_) {
        ACameraOutputTarget_create(previewWindow_, &previewTarget_);
        ACaptureRequest_addTarget(request_, previewTarget_);
    }

    if (ACameraCaptureSession_setRepeatingRequest(session_, nullptr, 1, &request_,
                                                  nullptr) != ACAMERA_OK) {
        LOGE("setRepeatingRequest failed");
        return false;
    }
    LOGI("camera streaming started (preview=%s)", previewWindow_ ? "yes" : "no");
    return true;
}

void CameraOcrSession::closeCameraLocked() {
    if (session_) {
        ACameraCaptureSession_stopRepeating(session_);
        ACameraCaptureSession_close(session_);
        session_ = nullptr;
    }
    if (request_) {
        ACaptureRequest_free(request_);
        request_ = nullptr;
    }
    if (readerTarget_) {
        ACameraOutputTarget_free(readerTarget_);
        readerTarget_ = nullptr;
    }
    if (previewTarget_) {
        ACameraOutputTarget_free(previewTarget_);
        previewTarget_ = nullptr;
    }
    if (outputs_) {
        ACaptureSessionOutputContainer_free(outputs_);
        outputs_ = nullptr;
    }
    if (readerOutput_) {
        ACaptureSessionOutput_free(readerOutput_);
        readerOutput_ = nullptr;
    }
    if (previewOutput_) {
        ACaptureSessionOutput_free(previewOutput_);
        previewOutput_ = nullptr;
    }
    if (device_) {
        ACameraDevice_close(device_);
        device_ = nullptr;
    }
}

// ---- Frame acquisition (OCR only) ------------------------------------------

void CameraOcrSession::onImageAvailable(void *ctx, AImageReader *reader) {
    static_cast<CameraOcrSession *>(ctx)->handleImage(reader);
}

void CameraOcrSession::handleImage(AImageReader *reader) {
    AImage *image = nullptr;
    if (AImageReader_acquireLatestImage(reader, &image) != AMEDIA_OK || image == nullptr)
        return;

    if (!running_) {
        AImage_delete(image);
        return;
    }

    // Frame-skip + drop-when-busy backpressure. The preview is unaffected — it
    // is a separate, direct camera output and runs at full framerate.
    frameCounter_++;
    bool process = (frameCounter_ % kFrameThreshold == 0);
    bool expected = false;
    if (process && busy_.compare_exchange_strong(expected, true)) {
        // Pack the YUV_420_888 planes into a contiguous NV21 buffer (Y plane
        // followed by interleaved V,U) for cv::COLOR_YUV2BGR_NV21.
        int32_t w = 0, h = 0;
        AImage_getWidth(image, &w);
        AImage_getHeight(image, &h);

        uint8_t *yData = nullptr, *uData = nullptr, *vData = nullptr;
        int yLen = 0, uLen = 0, vLen = 0;
        int yRowStride = 0, uRowStride = 0, vRowStride = 0;
        int uPixStride = 0, vPixStride = 0;
        AImage_getPlaneData(image, 0, &yData, &yLen);
        AImage_getPlaneData(image, 1, &uData, &uLen);
        AImage_getPlaneData(image, 2, &vData, &vLen);
        AImage_getPlaneRowStride(image, 0, &yRowStride);
        AImage_getPlaneRowStride(image, 1, &uRowStride);
        AImage_getPlaneRowStride(image, 2, &vRowStride);
        AImage_getPlanePixelStride(image, 1, &uPixStride);
        AImage_getPlanePixelStride(image, 2, &vPixStride);

        std::vector<uint8_t> nv21((size_t)w * h * 3 / 2);
        for (int row = 0; row < h; row++) {
            memcpy(nv21.data() + (size_t)row * w, yData + (size_t)row * yRowStride, w);
        }
        uint8_t *vu = nv21.data() + (size_t)w * h;
        for (int row = 0; row < h / 2; row++) {
            for (int col = 0; col < w / 2; col++) {
                size_t vIdx = (size_t)row * vRowStride + (size_t)col * vPixStride;
                size_t uIdx = (size_t)row * uRowStride + (size_t)col * uPixStride;
                *vu++ = vData[vIdx];
                *vu++ = uData[uIdx];
            }
        }

        {
            std::lock_guard<std::mutex> lk(frameMutex_);
            queuedNv21_ = std::move(nv21);
            frameReady_ = true;
        }
        frameCv_.notify_one();
    }

    AImage_delete(image);
}

// ---- OCR worker -------------------------------------------------------------

// Detector thread: converts each queued frame and runs ONLY the cheap Details
// detection. It always emits a result to Dart (so the ROI overlay tracks at the
// throttled frame rate, never blocked by OCR), and on a match pushes a job onto
// jobStack_ for the consumer to recognise.
void CameraOcrSession::detectorLoop() {
    while (true) {
        std::vector<uint8_t> nv21;
        {
            std::unique_lock<std::mutex> lk(frameMutex_);
            frameCv_.wait(lk, [&] { return frameReady_; });
            frameReady_ = false;
            if (!workerRunning_) break;
            nv21 = std::move(queuedNv21_);
        }
        if (nv21.empty()) {
            busy_ = false;
            continue;
        }

        cv::Mat bgr;
        try {
            cv::Mat yuv(analysisHeight_ * 3 / 2, analysisWidth_, CV_8UC1, nv21.data());
            cv::cvtColor(yuv, bgr, cv::COLOR_YUV2BGR_NV21);
            cv::rotate(bgr, bgr, cv::ROTATE_90_CLOCKWISE);
        } catch (cv::Exception &e) {
            LOGE("yuv convert failed: %s", e.what());
            busy_ = false;
            continue;
        }

        DebugImageType dbg = debug_ ? DebugImageType::ON : DebugImageType::NONE;
        DetailsDetectResult det;
        try {
            det = instance_->detect_details(
                bgr, static_cast<DetectionSide>(side_.load()), dbg);
        } catch (cv::Exception &e) {
            LOGE("detect_details failed: %s", e.what());
            busy_ = false;
            continue;
        }

        // Overlay result every frame: ROIs + detailsRoiIndex, no OCR strings.
        // BuildCCameraResult tolerates the empty ocrResults; the Dart listener
        // updates the overlay and only feeds the aggregator on full results.
        if (resultFn_) {
            CCameraResult *out = BuildCCameraResult(det.result, bgr.cols, bgr.rows);
            resultFn_(out);
        }

        // On a match, hand the heavy work to the consumer via the LIFO stack.
        if (det.matched) {
            {
                std::lock_guard<std::mutex> lk(jobMutex_);
                jobStack_.push_back(std::move(det));
                while (jobStack_.size() > kJobStackDepth)
                    jobStack_.pop_front(); // evict oldest on overflow
            }
            jobCv_.notify_one();
        }
        busy_ = false;
    }
}

// Consumer thread: pops the newest queued job (LIFO) and runs the expensive
// PaddleOCR pass, emitting the full result to Dart. Drains older jobs too —
// each is another vote into the Dart-side cross-frame aggregator.
void CameraOcrSession::consumerLoop() {
    while (true) {
        DetailsDetectResult job;
        {
            std::unique_lock<std::mutex> lk(jobMutex_);
            jobCv_.wait(lk, [&] { return !jobStack_.empty() || !workerRunning_; });
            if (!workerRunning_ && jobStack_.empty()) break;
            job = std::move(jobStack_.back()); // newest first
            jobStack_.pop_back();
        }

        const int w = job.inputImg.cols;
        const int h = job.inputImg.rows;
        ProcessImgResult res;
        try {
            res = instance_->recognise_details(job);
        } catch (cv::Exception &e) {
            LOGE("recognise_details failed: %s", e.what());
            continue;
        }

        if (resultFn_) {
            CCameraResult *out = BuildCCameraResult(res, w, h);
            resultFn_(out);
        }
    }
}

#endif // __ANDROID__
