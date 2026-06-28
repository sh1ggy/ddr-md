// Builds a COCRConfig from two flat arrays sent over the platform channel by
// ocr_processor.dart (buildCameraConfigArrays). Shared by the iOS (.mm) and
// Android (JNI) camera shims so the live-camera OCR uses the exact same
// calibration as lib/ocr_config.dart — NOT the C++ struct defaults, which
// diverge from the Dart source of truth.
//
// Field order MUST stay in lock-step with the Dart producer.
//
//   ints[0]  border
//   ints[1]  psm_eng
//   ints[2]  psm_engjp
//   ints[3]  gaussian_blur_size
//   ints[4]  tophat_kernel_size
//   ints[5]  morph_width
//   ints[6]  morph_height
//   ints[7..78]   roi[12][6]  (row-major)
//   ints[79..82]  combinedRoi[4]
//
//   doubles[0]  simplification_epsilon
//   doubles[1]  area_min_factor
//   doubles[2]  area_max_factor
//   doubles[3]  resolution_scale
//   doubles[4]  details_template_min_score
#pragma once

#include <cstdint>
#include "ddrocr_instance.h"

static const int kCfgIntCount = 83;
static const int kCfgDoubleCount = 5;

// Returns a COCRConfig built from the arrays, or the struct defaults if either
// array is the wrong size (defensive — keeps a malformed channel call from
// producing garbage geometry).
static inline COCRConfig BuildCOCRConfigFromArrays(const int32_t *ints, int ni,
                                                   const double *doubles, int nd) {
    COCRConfig cfg; // defaults
    if (ints == nullptr || doubles == nullptr || ni < kCfgIntCount ||
        nd < kCfgDoubleCount) {
        return cfg;
    }

    cfg.border = ints[0];
    cfg.psm_eng = ints[1];
    cfg.psm_engjp = ints[2];
    cfg.gaussian_blur_size = ints[3];
    cfg.tophat_kernel_size = ints[4];
    cfg.morph_width = ints[5];
    cfg.morph_height = ints[6];

    int k = 7;
    for (int r = 0; r < 12; r++) {
        for (int c = 0; c < 6; c++) {
            cfg.roi[r][c] = ints[k++];
        }
    }
    for (int c = 0; c < 4; c++) {
        cfg.combinedRoi[c] = ints[k++];
    }

    cfg.simplification_epsilon = doubles[0];
    cfg.area_min_factor = doubles[1];
    cfg.area_max_factor = doubles[2];
    cfg.resolution_scale = doubles[3];
    cfg.details_template_min_score = doubles[4];
    return cfg;
}
