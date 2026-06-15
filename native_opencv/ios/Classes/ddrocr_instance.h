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
    // Debug images captured when process_image is asked for them; empty
    // otherwise. debugMask is the full-frame binarized image (every frame);
    // debugDetailsCrop is the crop Tesseract matched on (only on a successful
    // Details match, so the UI can persist the last good one).
    cv::Mat debugMask;
    cv::Mat debugDetailsCrop;
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

class DdrocrInstance
{
public:
    std::string dataPath;
    std::string debugDir; // timestamped output directory for current run
    DdrocrInstance(std::string dataPath, const COCRConfig &cfg);
    ~DdrocrInstance();
    // TODO use outputimg path declared in class
    ProcessImgResult process_image(cv::Mat inputImg, DetectionSide side = DetectionSide::FIRST,
                                   DebugImageType debugImageType = DebugImageType::NONE);
    void setConfig(const COCRConfig &cfg);

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
