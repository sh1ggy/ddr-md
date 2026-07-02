#pragma once

#include <opencv2/opencv.hpp>
#include <string>
#include <stdint.h>
#include "ocr_wrapper.h"
#include "details_detector.h"

struct bounding_box
{
    int x1, y1, x2, y2;
    char *word;
    float confidence;
    int block_num, par_num, line_num, word_num;
};

struct bounding_boxes
{
    int length;
    struct bounding_box *boxes;
};

struct OCRResults
{
    OCRResult score;
    OCRResult marvelous;
    OCRResult perfect;
    OCRResult great;
    OCRResult good;
    OCRResult miss;
    OCRResult flare;
    OCRResult title;
    OCRResult username;
    OCRResult difficulty;
    OCRResult max_combo;
};

// Whether the pipeline should capture debug images for on-device inspection.
// Mirrors the Dart DebugImageType enum (same ordinal order).
enum class DebugImageType
{
    NONE = 0, // skip capture entirely (zero cost in the hot path)
    ON   = 1, // capture the full-frame mask and the matched Details crop
};

struct ProcessImgResult
{
    cv::Mat img;
    int32_t isDetected;
    std::vector<cv::Rect> rois;
    int32_t detailsRoiIndex;
    OCRResults ocrResults;
    // Details-badge template-match diagnostics (best match across all HSV
    // candidate blobs). Populated whenever classify() runs; -1 score means it
    // never ran (no candidates). detailsMatchScore is TM_CCOEFF_NORMED (0..1),
    // detailsMatchScale is the template scale of the winning match, and
    // detailsCandidateCount is how many HSV blobs were considered.
    float   detailsMatchScore  = -1.0f;
    float   detailsMatchScale  = 0.0f;
    int32_t detailsCandidateCount = 0;
    // Wall-clock timings (ms) for offline perf comparison. totalMs covers the
    // whole process_image call; combinedDetectRecMs is just the score-panel
    // detect+recognise (the model-dependent hot path). -1 = stage didn't run.
    int64_t totalMs            = -1;
    int64_t combinedDetectRecMs = -1;
    // Annotated combined-ROI crop: det boxes (green) + recognised text/conf and
    // per-field anchors (cyan). Populated only when debugImageType != NONE.
    // Empty when no warp/combined ROI was produced. The offline harness saves
    // this for high-value images; the app ignores it.
    cv::Mat detectAnnotated;
    // Debug images captured when process_image is asked for them; empty
    // otherwise. debugMask is the full-frame binarized image (every frame);
    // debugDetailsCrop is the crop the Details template matched on (only on a
    // successful Details match, so the UI can persist the last good one).
    cv::Mat debugMask;
    cv::Mat debugDetailsCrop;
    // Comprehensive all-field debug overlay drawn on the warped frame (field
    // ROIs + keys, paddle detections, combined ROI, anchors), cropped to the
    // warp's filled content. Populated only when debugImageType == ON and a warp
    // ran. The app shows it below the Details crop; also saved as roi_overlay.png.
    cv::Mat debugOverlay;
    // Full-color frame, set only on a successful "Details" match (independent of
    // the debug toggle). The stopped view paints the static ROIs over this last
    // good capture; the UI persists it and overwrites it on the next match.
    cv::Mat colorCapture;
};

// FFI-compatible config struct — layout must match the Dart COCRConfig Struct exactly.
// offset  0: border               int32_t
// offset  4: psm_eng              int32_t
// offset  8: psm_engjp            int32_t
// offset 12: gaussian_blur_size   int32_t
// offset 16: simplification_epsilon double  (16%8==0, no padding)
// offset 24: area_min_factor      double
// offset 32: area_max_factor      double
// offset 40: resolution_scale     double
// offset 48: tophat_kernel_size   int32_t
// offset 52: morph_width          int32_t  (HSV blob morphology kernel width)
// offset 56: morph_height         int32_t  (HSV blob morphology kernel height)
// offset 60: roi[12][6]           int32_t[72]
// total: 348 bytes
//
// roi row: {x1, y1, x2, y2, expand_x, expand_y}
// roi order: details(0), score(1), marvelous(2), perfect(3), great(4),
//            good(5), miss(6), flare(7), title(8), username(9),
//            difficulty(10), max_combo(11)
struct COCRConfig
{
    int32_t border                    = 30;
    int32_t psm_eng                   = 6;
    int32_t psm_engjp                 = 8;
    int32_t gaussian_blur_size        = 3;
    double  simplification_epsilon    = 0.07;
    double  area_min_factor           = 0.00082; // 0.082% of image area
    double  area_max_factor           = 0.0082;  // 0.82% of image area
    double  resolution_scale          = 3.0;     // upscale factor applied to each ROI before binarization
    int32_t tophat_kernel_size        = 125;     // morphological top-hat kernel size (must be odd)
    int32_t morph_width               = 360;     // HSV blob morphology opening kernel width
    int32_t morph_height              = 90;      // HSV blob morphology opening kernel height
    int32_t roi[12][6] = {
        {2054,2348,2418,2450, 0, 0}, // details
        {2700,2551,2968,2611, 5, 0}, // score
        {1896,2549,2018,2599, 0, 0}, // marvelous
        {1896,2608,2018,2657, 0, 4}, // perfect
        {1896,2664,2018,2702, 0, 6}, // great
        {1896,2727,2018,2771, 0, 5}, // good
        {1896,2825,2018,2879, 0, 0}, // miss
        {1649,2466,1817,2508, 0, 7}, // flare
        {1210,2075,1744,2133, 0,10}, // title
        {2180,1388,2465,1439,10,10}, // username
        {2056,1463,2627,1536,10,10}, // difficulty
        {2665,2779,2797,2831, 0, 0}, // max_combo
    };
    // Combined ROI {x1,y1,x2,y2} in warped 4000x5000 space — covers the score
    // panel. Fed to the PaddleOCR detection model; detected boxes are then
    // mapped to the score-panel fields via the per-field roi[] anchors above.
    int32_t combinedRoi[4] = {1648, 2439, 2959, 2848};
    // DetailsDetector::classify threshold (TM_CCOEFF_NORMED). See
    // ocr_config.dart::ocrDetailsTemplateMinScore for the source of truth.
    double  details_template_min_score = 0.55;
};

enum class DetectionSide
{
    FIRST = 0, // Default: use OCR to locate the "Details" region
    LEFT  = 1, // Pick the spatially leftmost detected ROI
    RIGHT = 2, // Pick the spatially rightmost detected ROI
};

// Output of the cheap "phase 1" Details detection (HSV mask -> blobs ->
// template match). Carries everything the expensive "phase 2" OCR
// (recognise_details) needs, so the two can run on separate threads: the
// detector thread produces this every frame, the consumer thread pops it and
// runs recognise_details only when a badge was found.
struct DetailsDetectResult
{
    // result holds the phase-1 fields already populated (isDetected, rois,
    // detailsRoiIndex, detailsMatch* diagnostics, debugMask/debugDetailsCrop,
    // colorCapture). recognise_details fills in the rest (ocrResults, timings).
    ProcessImgResult result;
    // True when a Details badge matched (result.detailsRoiIndex >= 0) AND there
    // is enough geometry to run phase 2. When false the consumer skips OCR and
    // the partial `result` is final.
    bool matched = false;
    // Phase-2 inputs, valid only when matched. inputImg is a clone owned by this
    // struct so it survives the hand-off to the consumer thread. chosenHull is
    // contours_final[correct_roi_idx] — the contour the homography warp uses.
    cv::Mat inputImg;
    std::vector<cv::Point> chosenHull;
    DetectionSide side = DetectionSide::FIRST;
    DebugImageType debugImageType = DebugImageType::NONE;
};

class DdrocrInstance
{
public:
    std::string dataPath;
    std::string debugDir; // timestamped output directory for current run
    // When false, process_image skips creating the on-disk debug dir / writing
    // PNGs even if debugImageType==ON — it still populates in-memory debug
    // fields on ProcessImgResult (e.g. detectAnnotated). The offline harness
    // sets this false to get the annotated crop without littering dataPath.
    bool diskDebug = true;
    DdrocrInstance(std::string dataPath, const COCRConfig &cfg,
                   const ModelSet *models = nullptr);
    ~DdrocrInstance();
    // TODO use outputimg path declared in class
    // Full pipeline: detect_details followed by recognise_details (when a badge
    // matched). Kept for the picked-image FFI path and offline tooling.
    ProcessImgResult process_image(cv::Mat inputImg, DetectionSide side = DetectionSide::FIRST,
                                   DebugImageType debugImageType = DebugImageType::NONE);
    // Phase 1 (cheap, run every frame): HSV mask -> blob filter -> Details
    // template match. Returns the detected ROIs + chosen index plus the geometry
    // phase 2 needs. Does NOT run any PaddleOCR.
    DetailsDetectResult detect_details(cv::Mat inputImg,
                                       DetectionSide side = DetectionSide::FIRST,
                                       DebugImageType debugImageType = DebugImageType::NONE);
    // Phase 2 (expensive, run from the consumer thread): homography warp +
    // PaddleOCR det/rec over the score panel. Consumes a matched
    // DetailsDetectResult and returns the completed ProcessImgResult.
    ProcessImgResult recognise_details(const DetailsDetectResult &det);
    void setConfig(const COCRConfig &cfg);
    // Re-read the Details template from disk (see DetailsDetector::reload).
    // Called on camera start so a template copied/updated after this instance
    // was constructed takes effect without an app rebuild.
    void reloadDetailsTemplate() { detailsDetector.reload(); }

private:
    COCRConfig config;
    // Helper methods
    OCRWrapper ocrWrapper;
    DetailsDetector detailsDetector;
    cv::Mat otsuToLogical(const cv::Mat &gray, bool invert = false) const;
    cv::Mat logicalToDisplayU8(const cv::Mat &logical) const;
    cv::Rect expandRoi(cv::Rect roi, cv::Point expand);
    std::vector<cv::Point2f> rectToPoints(const cv::Rect &r);
    cv::Rect offsetToRoi(cv::Point tl, cv::Point br, cv::Point expansion = {0, 0});
    char classifyDigit_0_or_1(const cv::Mat &input);

    OCRResult getPreprocessedRoiImage(
        const cv::Mat &warpedImg,
        const cv::Rect &ROI_Target,
        const cv::Rect &ROI_Details,
        const cv::Point &warped_details_top_left,
        const cv::Point &expand,
        const std::string &imageName,
        OCRType type);

    void save_img(const std::string &fileName, cv::Mat img);
};
