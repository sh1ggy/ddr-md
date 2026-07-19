// Shared C-ABI result type for the native camera/OCR pipeline. Both the iOS
// (.mm) and Android (NDK) sessions marshal a ProcessImgResult into a
// CCameraResult and hand the pointer to Dart via an FFI NativeCallable — there
// is NO platform channel / JNI in the result path. Dart reads the fields (see
// ProcessResult.fromNative in ocr_processor.dart) and frees it with
// camera_free_result.
//
// The struct layout MUST match the Dart `CCameraResult extends Struct`.
#pragma once

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <opencv2/opencv.hpp>
#include "ddrocr_instance.h"

extern "C" {

struct CCameraResult {
  int32_t isDetected;
  int32_t detailsRoiIndex;
  int32_t width;   // processed-frame dims (the ROI pixel space)
  int32_t height;
  int32_t roisCount;
  int32_t *rois;   // flat {x,y,w,h} * roisCount
  char *score;
  char *marvelous;
  char *perfect;
  char *great;
  char *good;
  char *miss;
  char *flare;
  char *title;
  char *username;
  char *difficulty;
  char *maxCombo;
  char *exScore;
  uint8_t *mask;   int32_t maskLen;     // PNG, full-frame binarized (debug)
  uint8_t *crop;   int32_t cropLen;     // PNG, matched Details crop (debug)
  uint8_t *capture; int32_t captureLen; // JPEG, color frame on a match
  uint8_t *overlay; int32_t overlayLen; // PNG, all-field warped debug overlay
};

// Function pointer Dart registers (NativeCallable). Invoked once per processed
// frame from the native OCR worker thread; ownership of `result` passes to Dart.
typedef void (*CameraResultFn)(struct CCameraResult *result);

} // extern "C"

// ---- marshalling helpers (header-internal) ---------------------------------

// On allocation failure returns nullptr, which the Dart reader maps to ''.
static inline char *ccr_dup(const std::string &s) {
  char *p = (char *)malloc(s.size() + 1);
  if (p) memcpy(p, s.c_str(), s.size() + 1);
  return p;
}

static inline void ccr_encode(const cv::Mat &img, const char *ext,
                              uint8_t **out, int32_t *len) {
  *out = nullptr;
  *len = 0;
  if (img.empty()) return;
  std::vector<uchar> buf;
  if (cv::imencode(ext, img, buf) && !buf.empty()) {
    *out = (uint8_t *)malloc(buf.size());
    if (*out == nullptr) return;
    memcpy(*out, buf.data(), buf.size());
    *len = (int32_t)buf.size();
  }
}

// Allocates a CCameraResult (malloc) from a ProcessImgResult. Dart owns the
// returned pointer and releases it via camera_free_result.
static inline CCameraResult *BuildCCameraResult(const ProcessImgResult &r,
                                                int width, int height) {
  CCameraResult *c = (CCameraResult *)calloc(1, sizeof(CCameraResult));
  if (c == nullptr) return nullptr;
  c->isDetected = r.isDetected;
  c->detailsRoiIndex = r.detailsRoiIndex;
  c->width = width;
  c->height = height;
  c->roisCount = (int32_t)r.rois.size();
  if (c->roisCount > 0) {
    c->rois = (int32_t *)malloc(sizeof(int32_t) * 4 * c->roisCount);
    if (c->rois == nullptr) {
      c->roisCount = 0;
    } else {
      for (size_t i = 0; i < r.rois.size(); i++) {
        c->rois[i * 4 + 0] = r.rois[i].x;
        c->rois[i * 4 + 1] = r.rois[i].y;
        c->rois[i * 4 + 2] = r.rois[i].width;
        c->rois[i * 4 + 3] = r.rois[i].height;
      }
    }
  }
  const auto &o = r.ocrResults;
  c->score = ccr_dup(o.score.text);
  c->marvelous = ccr_dup(o.marvelous.text);
  c->perfect = ccr_dup(o.perfect.text);
  c->great = ccr_dup(o.great.text);
  c->good = ccr_dup(o.good.text);
  c->miss = ccr_dup(o.miss.text);
  c->flare = ccr_dup(o.flare.text);
  c->title = ccr_dup(o.title.text);
  c->username = ccr_dup(o.username.text);
  c->difficulty = ccr_dup(o.difficulty.text);
  c->maxCombo = ccr_dup(o.max_combo.text);
  c->exScore = ccr_dup(o.ex_score.text);
  ccr_encode(r.debugMask, ".png", &c->mask, &c->maskLen);
  ccr_encode(r.debugDetailsCrop, ".png", &c->crop, &c->cropLen);
  ccr_encode(r.colorCapture, ".jpg", &c->capture, &c->captureLen);
  ccr_encode(r.debugOverlay, ".png", &c->overlay, &c->overlayLen);
  return c;
}

static inline void FreeCCameraResult(CCameraResult *c) {
  if (!c) return;
  free(c->rois);
  free(c->score);
  free(c->marvelous);
  free(c->perfect);
  free(c->great);
  free(c->good);
  free(c->miss);
  free(c->flare);
  free(c->title);
  free(c->username);
  free(c->difficulty);
  free(c->maxCombo);
  free(c->exScore);
  free(c->mask);
  free(c->crop);
  free(c->capture);
  free(c->overlay);
  free(c);
}
