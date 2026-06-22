#include "ddrocr_instance.h"
#include <chrono>
#include <cstring>
#include <algorithm>
#include <map>
#include <set>
#include <sstream>
#include <iomanip>
#include <sys/stat.h>

#ifdef __ANDROID__
#include <android/log.h>
#endif

extern void platform_log(const char *fmt, ...);

//These functions are divergent between testebed and regular
void DdrocrInstance::save_img(const std::string &fileName, cv::Mat img)
{
    #ifdef NDEBUG
        return;
    #endif
    if (debugDir.empty())
        return;
    char path[512];
    snprintf(path, sizeof(path), "%s/%s.png", debugDir.c_str(), fileName.c_str());
    platform_log("wrote: %s\n", path);
    cv::imwrite(path, img);
}

const int max_value_H = 360 / 2;
const int max_value = 255;

// ROI indices into config.roi[N] — order matches ocr_config.txt
static const int ROI_IDX_DETAILS    = 0;
static const int ROI_IDX_SCORE      = 1;
static const int ROI_IDX_MARVELOUS  = 2;
static const int ROI_IDX_PERFECT    = 3;
static const int ROI_IDX_GREAT      = 4;
static const int ROI_IDX_GOOD       = 5;
static const int ROI_IDX_MISS       = 6;
static const int ROI_IDX_FLARE      = 7;
static const int ROI_IDX_TITLE      = 8;
static const int ROI_IDX_USERNAME   = 9;
static const int ROI_IDX_DIFFICULTY = 10;
static const int ROI_IDX_MAXCOMBO   = 11;

DdrocrInstance::DdrocrInstance(std::string dataPath, const COCRConfig &cfg,
                               const ModelSet *models)
    : dataPath(dataPath), ocrWrapper(dataPath, models), detailsDetector(dataPath)
{
    setConfig(cfg);
    platform_log("DdrocrInstance initialized (template-based details=%s)\n",
                 detailsDetector.hasTemplate() ? "ON" : "OFF (fallback)");
}

DdrocrInstance::~DdrocrInstance()
{
    platform_log("DdrocrInstance destroyed\n");
}

void DdrocrInstance::setConfig(const COCRConfig &cfg)
{
    config = cfg;
    platform_log("setConfig: border=%d gaussian=%d epsilon=%.3f\n",
                 cfg.border, cfg.gaussian_blur_size, cfg.simplification_epsilon);
}

cv::Mat DdrocrInstance::otsuToLogical(const cv::Mat &gray, bool invert) const
{
    cv::Mat gray8;
    if (gray.channels() == 1)
    {
        if (gray.depth() == CV_8U)
            gray8 = gray;
        else
            gray.convertTo(gray8, CV_8U);
    }
    else
    {
        cv::Mat grayConverted;
        cv::cvtColor(gray, grayConverted, cv::COLOR_BGR2GRAY);
        if (grayConverted.depth() == CV_8U)
            gray8 = grayConverted;
        else
            grayConverted.convertTo(gray8, CV_8U);
    }

    cv::Mat binary255;
    const int type = invert ? (cv::THRESH_BINARY_INV | cv::THRESH_OTSU)
                            : (cv::THRESH_BINARY | cv::THRESH_OTSU);
    cv::threshold(gray8, binary255, 0, 255, type);

    cv::Mat logical;
    binary255.convertTo(logical, CV_8U, 1.0 / 255.0);
    return logical;
}

cv::Mat DdrocrInstance::logicalToDisplayU8(const cv::Mat &logical) const
{
    if (logical.empty())
        return logical;

    cv::Mat logical8;
    if (logical.depth() == CV_8U)
        logical8 = logical;
    else
        logical.convertTo(logical8, CV_8U);

    cv::Mat display;
    display = logical8 * 255;
    return display;
}

// ---------------------------------------------------------------------------
// Phase 1: cheap Details detection. Runs every frame on the detector thread.
// Returns a DetailsDetectResult whose `result` holds the overlay/diagnostic
// fields; when `matched` is true it also carries the geometry recognise_details
// needs. NO PaddleOCR runs here.
// ---------------------------------------------------------------------------
DetailsDetectResult DdrocrInstance::detect_details(cv::Mat inputImg, DetectionSide side,
                                                   DebugImageType debugImageType)
{
    DetailsDetectResult det;
    det.side = side;
    det.debugImageType = debugImageType;
    ProcessImgResult &result = det.result;

    // Create a timestamped directory for all debug images from this run.
    // Only when debug capture is requested — otherwise (e.g. the offline
    // model-compare harness, which passes NONE) we'd litter dataPath with an
    // empty timestamped dir on every frame.
    if (debugImageType != DebugImageType::NONE && diskDebug)
    {
        auto now = std::chrono::system_clock::now();
        auto time_t_now = std::chrono::system_clock::to_time_t(now);
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      now.time_since_epoch()) %
                  1000;
        std::tm tm_buf;
        localtime_r(&time_t_now, &tm_buf);

        std::ostringstream oss;
        oss << dataPath << "/ocr_debug_"
            << std::put_time(&tm_buf, "%Y%m%d_%H%M%S")
            << "_" << std::setfill('0') << std::setw(3) << ms.count();
        debugDir = oss.str();
        mkdir(debugDir.c_str(), 0755);
        // ocr_input_*.png crops (one per recognised box) live in a rois/
        // subdir to keep the parent dir scannable.
        const std::string roisDir = debugDir + "/rois";
        mkdir(roisDir.c_str(), 0755);
        ocrWrapper.debugDir = roisDir;
        platform_log("[DEBUG] output dir: %s\n", debugDir.c_str());
    }

    auto t_total_start = std::chrono::high_resolution_clock::now();
    auto checkpoint = [&](const char *label, std::chrono::high_resolution_clock::time_point &ref) {
        auto now = std::chrono::high_resolution_clock::now();
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - ref).count();
        platform_log("[TIMER] %s: %lld ms\n", label, (long long)ms);
        ref = now;
    };
    auto t_rolling_timer = t_total_start;

    // Selecting Details box - HSV mask
    cv::Mat imgHSV;
    cv::cvtColor(inputImg, imgHSV, cv::COLOR_BGR2HSV);

    double channel1Min = 0.380;
    double channel1Max = 0.531;
    double channel2Min = 0.204;
    double channel2Max = 1.000;
    double channel3Min = 0.592;
    double channel3Max = 1.000;

    // Use inRange for HSV thresholding
    cv::Scalar lowerHSV(channel1Min * max_value_H, channel2Min * max_value, channel3Min * max_value);
    cv::Scalar upperHSV(channel1Max * max_value_H, channel2Max * max_value, channel3Max * max_value);

    cv::Mat BW_HSV;
    cv::inRange(imgHSV, lowerHSV, upperHSV, BW_HSV);

    checkpoint("Threshholding", t_rolling_timer);

    // Do blob detection and filter small blobs
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(BW_HSV, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    cv::Mat BW2 = cv::Mat::zeros(inputImg.rows, inputImg.cols, CV_8U);

    // Area thresholds as a percentage of current image area
    double imgArea = static_cast<double>(inputImg.cols * inputImg.rows);
    double areaMin = imgArea * config.area_min_factor;
    double areaMax = imgArea * config.area_max_factor;
    for (size_t i = 0; i < contours.size(); i++)
    {
        double area = cv::contourArea(contours[i]);
        if (area >= areaMin && area <= areaMax)
        {
            cv::drawContours(BW2, contours, i, cv::Scalar(255), cv::FILLED);
        }
    }

    checkpoint("Blob filtering", t_rolling_timer);

    // double morph_scale_factor = 0.3;
    // cv::resize(BW2, BW2, cv::Size(), morph_scale_factor, morph_scale_factor, cv::INTER_AREA);

    int m = config.morph_width;
    int n = config.morph_height;

    // Create opening kernel using byte array (faster than getStructuringElement)
    int open_width = m * 0.1;
    int open_height = n * 0.1;
    uchar *open_data = new uchar[open_height * open_width];
    memset(open_data, 255, open_height * open_width);
    cv::Mat SE_open(open_height, open_width, CV_8U, open_data);

    cv::Mat BW3;
    cv::morphologyEx(BW2, BW3, cv::MORPH_OPEN, SE_open);
    save_img("BW_HSV", BW_HSV);
    save_img("BW2", BW2);
    save_img("BW3", BW3);
    checkpoint("morphologyEx OPEN + contours", t_rolling_timer);

    delete[] open_data;

    // Get bounding boxes
    std::vector<std::vector<cv::Point>> contours_final;
    cv::findContours(BW3.clone(), contours_final, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    std::vector<cv::Rect> detectedRois;

    int largestRoiAreaIndex = 0;
    double largestRoiArea = 0;

    // Looping through contours to find its area & bounding box
    for (size_t i = 0; i < contours_final.size(); i++)
    {
        double thisRoi = cv::contourArea(contours_final[i]);
        detectedRois.push_back(cv::boundingRect(contours_final[i]));

        if (thisRoi > largestRoiArea)
        {
            largestRoiAreaIndex = i;
            largestRoiArea = thisRoi;
        }
    }

    // // Scale bounding boxes back to original image size
    // for (size_t i = 0; i < detectedRois.size(); i++)
    // {
    //     detectedRois[i].x /= morph_scale_factor;
    //     detectedRois[i].y /= morph_scale_factor;
    //     detectedRois[i].width /= morph_scale_factor;
    //     detectedRois[i].height /= morph_scale_factor;
    // }

    if (detectedRois.size() == 0)
    {
        platform_log("No OCR ROI detected, defaulting to full image\n");
        result.isDetected = 0;
        return det;
    }

    // Debug: hand back the HSV mask as the debug overlay
    if (debugImageType == DebugImageType::ON)
        result.debugMask = BW_HSV;

    checkpoint("image preprocessing", t_rolling_timer);

    // ----- Details detection via template matching -----
    // DetailsDetector uses cv::matchTemplate against a stored reference crop —
    // deterministic and fast, since the "Details" badge is a fixed UI element.
    //
    // If no template ships with the build, classify() returns -1 and we report
    // "no Details ROI matched" — the same failure mode the previous OCR-based
    // path produced when nothing matched.
    //
    // ALWAYS save every candidate crop to details_rois/ so a failed detection
    // can be diagnosed by inspecting what was actually fed to matchTemplate.
    std::string detailsRoiDir;
    if (!debugDir.empty())
    {
        detailsRoiDir = debugDir + "/details_rois";
        mkdir(detailsRoiDir.c_str(), 0755);
        for (size_t i = 0; i < detectedRois.size(); ++i)
        {
            cv::Rect bound = detectedRois[i] &
                             cv::Rect(0, 0, inputImg.cols, inputImg.rows);
            if (bound.width <= 0 || bound.height <= 0) continue;
            char stem[512];
            snprintf(stem, sizeof(stem), "details_rois/cand_%zu_input", i);
            save_img(stem, inputImg(bound));
        }
    }

    detailsDetector.debugDir = debugDir;
    const float minScore = (float)config.details_template_min_score;
    DetailsDetector::Match dmatch =
        detailsDetector.classify(inputImg, detectedRois, minScore);

    // Surface template-match diagnostics for offline tooling/debug.
    result.detailsMatchScore     = dmatch.score;
    result.detailsMatchScale     = dmatch.scale;
    result.detailsCandidateCount = (int32_t)detectedRois.size();

    // For DetectionSide::LEFT/RIGHT we need *all* viable matches, not just
    // the best one. Re-run a small loop to collect every candidate that
    // cleared the same threshold, then pick by side.
    std::vector<int> detectedDetailsIndices;
    if (dmatch.index >= 0)
    {
        if (side == DetectionSide::FIRST)
        {
            detectedDetailsIndices.push_back(dmatch.index);
        }
        else
        {
            for (size_t i = 0; i < detectedRois.size(); ++i)
            {
                std::vector<cv::Rect> one{detectedRois[i]};
                auto m = detailsDetector.classify(inputImg, one, minScore);
                if (m.index == 0)
                    detectedDetailsIndices.push_back((int)i);
            }
            if (detectedDetailsIndices.empty())
                detectedDetailsIndices.push_back(dmatch.index);
        }
    }

    cv::Mat roi_img = inputImg.clone();
    for (size_t i = 0; i < detectedRois.size(); i++)
        cv::rectangle(roi_img, detectedRois[i], cv::Scalar(0, 255, 0), 4);
    save_img("roi_img", roi_img);

    int correct_roi_idx = -1;

    checkpoint("details template match", t_rolling_timer);

    auto t_full_details_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::high_resolution_clock::now() - t_total_start).count();
    platform_log("[TIMER] full details detection: %lld ms\n", (long long)t_full_details_ms);

    result.isDetected = 1;
    result.rois = detectedRois;
    save_img("BW3", BW3);

    if (detectedDetailsIndices.empty())
    {
        auto t_total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::high_resolution_clock::now() - t_total_start).count();
        platform_log("[TIMER] process_image total (no Details found): %lld ms\n", (long long)t_total_ms);
        platform_log("Details template match failed (best score=%.3f). Defaulting to no match.\n", dmatch.score);
        result.detailsRoiIndex = -1;
        return det;
    }

    // Pick correct_roi_idx from detectedDetailsIndices based on DetectionSide
    if (side == DetectionSide::LEFT)
    {
        correct_roi_idx = detectedDetailsIndices[0];
        for (int idx : detectedDetailsIndices)
        {
            if (detectedRois[idx].x < detectedRois[correct_roi_idx].x)
                correct_roi_idx = idx;
        }
        platform_log("DetectionSide::LEFT selected ROI %d (x=%d)\n", correct_roi_idx, detectedRois[correct_roi_idx].x);
    }
    else if (side == DetectionSide::RIGHT)
    {
        correct_roi_idx = detectedDetailsIndices[0];
        for (int idx : detectedDetailsIndices)
        {
            if (detectedRois[idx].x > detectedRois[correct_roi_idx].x)
                correct_roi_idx = idx;
        }
        platform_log("DetectionSide::RIGHT selected ROI %d (x=%d)\n", correct_roi_idx, detectedRois[correct_roi_idx].x);
    }
    else
    {
        // FIRST: best template match wins.
        correct_roi_idx = detectedDetailsIndices[0];
    }
    result.detailsRoiIndex = correct_roi_idx;

    // Debug ON: hand back the matched candidate crop so the UI can show it.
    if (debugImageType == DebugImageType::ON && correct_roi_idx >= 0)
    {
        cv::Rect bound = detectedRois[correct_roi_idx] &
                         cv::Rect(0, 0, inputImg.cols, inputImg.rows);
        if (bound.width > 0 && bound.height > 0)
            result.debugDetailsCrop = inputImg(bound).clone();
    }

    // Always (regardless of the debug toggle) hand back the full-color frame for
    // a successful match — the stopped view paints the static ROIs over this last
    // good capture. Clone so the FFI encode is decoupled from the input buffer.
    if (correct_roi_idx >= 0 && !inputImg.empty())
        result.colorCapture = inputImg.clone();

    // ----- End of phase 1 -----
    // A badge matched. Phase 2 (recognise_details) needs the chosen contour to
    // build the homography. If we don't have a usable contour for it, treat this
    // as detected-but-not-recognisable and let the consumer skip OCR.
    if (correct_roi_idx >= 0 &&
        correct_roi_idx < (int)result.rois.size() &&
        correct_roi_idx < (int)contours_final.size())
    {
        det.matched = true;
        det.inputImg = inputImg.clone(); // owned hand-off to the consumer thread
        det.chosenHull = contours_final[correct_roi_idx];
    }
    else
    {
        platform_log("Not enough ROIs detected, defaulting to first detected ROI\n");
        result.isDetected = 1;
    }
    return det;
}

// ---------------------------------------------------------------------------
// Phase 2: expensive homography warp + PaddleOCR det/rec. Runs on the consumer
// thread from a matched DetailsDetectResult.
// ---------------------------------------------------------------------------
ProcessImgResult DdrocrInstance::recognise_details(const DetailsDetectResult &det)
{
    ProcessImgResult result = det.result;
    if (!det.matched)
        return result;

    const cv::Mat &inputImg = det.inputImg;
    const DetectionSide side = det.side;
    const DebugImageType debugImageType = det.debugImageType;
    const int correct_roi_idx = result.detailsRoiIndex;
    const std::vector<cv::Rect> &detectedRois = result.rois;

    auto t_total_start = std::chrono::high_resolution_clock::now();

    // Create offsets for score OCR (driven by config)
    auto roiRect = [&](int i) {
        return offsetToRoi(cv::Point(config.roi[i][0], config.roi[i][1]),
                           cv::Point(config.roi[i][2], config.roi[i][3]));
    };
    cv::Rect ROI_Score      = roiRect(ROI_IDX_SCORE);
    cv::Rect ROI_Details    = roiRect(ROI_IDX_DETAILS);
    cv::Rect ROI_Marvelous  = roiRect(ROI_IDX_MARVELOUS);
    cv::Rect ROI_Perfect    = roiRect(ROI_IDX_PERFECT);
    cv::Rect ROI_Great      = roiRect(ROI_IDX_GREAT);
    cv::Rect ROI_Good       = roiRect(ROI_IDX_GOOD);
    cv::Rect ROI_Miss       = roiRect(ROI_IDX_MISS);
    cv::Rect ROI_Flare      = roiRect(ROI_IDX_FLARE);
    cv::Rect ROI_Title      = roiRect(ROI_IDX_TITLE);
    cv::Rect ROI_Username   = roiRect(ROI_IDX_USERNAME);
    cv::Rect ROI_Difficulty = roiRect(ROI_IDX_DIFFICULTY);
    cv::Rect ROI_MaxCombo   = roiRect(ROI_IDX_MAXCOMBO);

    // Using regionprops Convex hull method (det.chosenHull is the contour the
    // detector picked for the matched Details ROI).
    std::vector<cv::Point> hull;
    cv::convexHull(det.chosenHull, hull);

    // Approximate polygon
    std::vector<cv::Point> approx;
    // TODO: This needs tweaking and optim
    double epsilon = config.simplification_epsilon * cv::arcLength(hull, true);
    cv::approxPolyDP(hull, approx, epsilon, true);

    cv::Mat approx_img = inputImg.clone();
    for (size_t i = 0; i < approx.size(); i++)
    {
        cv::line(approx_img, approx[i], approx[(i + 1) % approx.size()],
                 cv::Scalar(0, 255, 0), 4);
        cv::circle(approx_img, approx[i], 12, cv::Scalar(0, 255, 255), -1);
    }

    save_img("extrema", approx_img);

    // Get first 4 points and order them
    std::vector<cv::Point2f> pts;
    for (int i = 0; i < std::min(4, (int)approx.size()); i++)
    {
        pts.push_back(cv::Point2f(approx[i].x, approx[i].y));
    }

    // Order points: top-left, top-right, bottom-right, bottom-left
    std::vector<std::pair<float, int>> sums;
    for (int i = 0; i < pts.size(); i++)
    {
        sums.push_back(std::make_pair(pts[i].x + pts[i].y, i));
    }
    std::sort(sums.begin(), sums.end());

    if (sums.size() < 4)
    {
        platform_log("Not enough points for homography, defaulting to first detected ROI\n");
        result.isDetected = 1;
        return result;
    }

    cv::Point2f tl = pts[sums[0].second];
    cv::Point2f br = pts[sums[3].second];

    cv::Point2f remaining[2] = {pts[sums[1].second], pts[sums[2].second]};
    cv::Point2f tr = remaining[0].x > remaining[1].x ? remaining[0] : remaining[1];
    cv::Point2f bl = remaining[0].x < remaining[1].x ? remaining[0] : remaining[1];

    std::vector<cv::Point2f> detailsPoints = {tl, tr, br, bl};
    // Perform homography
    std::vector<cv::Point2f> detailsReferencePoints = rectToPoints(ROI_Details);
    cv::Mat H = cv::getPerspectiveTransform(detailsPoints, detailsReferencePoints);

    cv::Mat warpedImg;
    cv::Size beeg = cv::Size(4000, 5000);
    cv::warpPerspective(inputImg, warpedImg, H, beeg);

    save_img("warped", warpedImg);

    // Read from offsets
    std::vector<cv::Point2f> tl_vec = {tl};
    std::vector<cv::Point2f> tl_transformed;
    cv::perspectiveTransform(tl_vec, tl_transformed, H);

    cv::Point2f warped_details_top_left = tl_transformed[0];

    OCRResults ocrResults = {};

    auto expand = [&](int i) {
        return cv::Point(config.roi[i][4], config.roi[i][5]);
    };

    // ----- Score-panel: det+rec over the combined ROI -----
    //
    // We run the PaddleOCR detection model over a single rectangle covering
    // the score panel, then map each detected text box back to one of the
    // score-panel fields by spatial overlap with that field's anchor rect
    // (the per-field rectangles in config.roi[]). This avoids brittle tight
    // per-field crops and lets the model produce its preferred bbox.
    cv::Rect ROI_Combined = offsetToRoi(
        cv::Point(config.combinedRoi[0], config.combinedRoi[1]),
        cv::Point(config.combinedRoi[2], config.combinedRoi[3]));
    cv::Point2d combinedOffset(
        ROI_Combined.x - ROI_Details.x,
        ROI_Combined.y - ROI_Details.y);
    cv::Rect roi_combined_warped(
        warped_details_top_left.x + combinedOffset.x,
        warped_details_top_left.y + combinedOffset.y,
        ROI_Combined.width,
        ROI_Combined.height);
    roi_combined_warped &= cv::Rect(0, 0, warpedImg.cols, warpedImg.rows);

    // Map a per-field anchor rect (in config-roi coords) into combinedCrop
    // local coords. Used by the picker below and by the debug renderer.
    auto fieldInCombinedCrop = [&](const cv::Rect &fieldRoi) -> cv::Rect {
        cv::Point2d fOff(fieldRoi.x - ROI_Combined.x,
                         fieldRoi.y - ROI_Combined.y);
        return cv::Rect(
            (int)std::round(fOff.x), (int)std::round(fOff.y),
            fieldRoi.width, fieldRoi.height);
    };

    std::vector<DetectedText> detections;
    if (roi_combined_warped.width > 0 && roi_combined_warped.height > 0)
    {
        cv::Mat combinedCrop = warpedImg(roi_combined_warped);
        save_img("roi_combined", combinedCrop);
        auto t0 = std::chrono::high_resolution_clock::now();
        detections = ocrWrapper.performDetectAndRecognise(
            combinedCrop, OCRType::Digit, "combined");
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::high_resolution_clock::now() - t0).count();
        result.combinedDetectRecMs = (int64_t)ms;
        platform_log("[TIMER] combined detect+rec: %lld ms, %zu boxes\n",
                     (long long)ms, detections.size());

        // When the debug toggle is on, render an annotated view of what
        // PaddleOCR actually saw: detection boxes (green) with recognised text
        // + confidence, and the per-field anchor rectangles (cyan) the picker
        // matches detections against. Written to debugDir as paddle_detect.png
        // (cv::imwrite directly so it survives NDEBUG release builds).
        if (debugImageType == DebugImageType::ON)
        {
            cv::Mat annotated;
            if (combinedCrop.channels() == 1)
                cv::cvtColor(combinedCrop, annotated, cv::COLOR_GRAY2BGR);
            else
                annotated = combinedCrop.clone();

            const std::pair<const char *, cv::Rect> anchors[] = {
                {"score",     fieldInCombinedCrop(ROI_Score)},
                {"marvelous", fieldInCombinedCrop(ROI_Marvelous)},
                {"perfect",   fieldInCombinedCrop(ROI_Perfect)},
                {"great",     fieldInCombinedCrop(ROI_Great)},
                {"good",      fieldInCombinedCrop(ROI_Good)},
                {"miss",      fieldInCombinedCrop(ROI_Miss)},
                {"flare",     fieldInCombinedCrop(ROI_Flare)},
                {"max_combo", fieldInCombinedCrop(ROI_MaxCombo)},
            };
            const cv::Rect cropBounds(0, 0, annotated.cols, annotated.rows);
            for (const auto &a : anchors)
            {
                cv::Rect r = a.second & cropBounds;
                if (r.width <= 0 || r.height <= 0) continue;
                cv::rectangle(annotated, r, cv::Scalar(255, 255, 0), 1);
                cv::putText(annotated, a.first,
                            cv::Point(r.x + 2, r.y + 12),
                            cv::FONT_HERSHEY_SIMPLEX, 0.35,
                            cv::Scalar(255, 255, 0), 1, cv::LINE_AA);
            }

            for (const auto &d : detections)
            {
                cv::rectangle(annotated, d.box, cv::Scalar(0, 255, 0), 2);
                char label[128];
                snprintf(label, sizeof(label), "%s (%.2f)",
                         d.result.text.c_str(), d.result.confidence);
                int baseline = 0;
                cv::Size ts = cv::getTextSize(label, cv::FONT_HERSHEY_SIMPLEX,
                                              0.4, 1, &baseline);
                int ty = std::max(ts.height + 2, d.box.y - 2);
                cv::rectangle(annotated,
                              cv::Rect(d.box.x, ty - ts.height - 2,
                                       ts.width + 4, ts.height + 4),
                              cv::Scalar(0, 0, 0), cv::FILLED);
                cv::putText(annotated, label,
                            cv::Point(d.box.x + 2, ty),
                            cv::FONT_HERSHEY_SIMPLEX, 0.4,
                            cv::Scalar(0, 255, 0), 1, cv::LINE_AA);
            }

            // Hand the annotated crop back to the caller (offline harness uses
            // it). Only write to disk when an app debug dir is configured.
            result.detectAnnotated = annotated;
            if (!debugDir.empty())
            {
                char path[512];
                snprintf(path, sizeof(path), "%s/paddle_detect.png", debugDir.c_str());
                cv::imwrite(path, annotated);
                platform_log("wrote: %s (%zu det boxes)\n", path, detections.size());
            }
        }
    }

    auto pickBestDetection = [&](const cv::Rect &fieldRoi) -> OCRResult {
        cv::Rect anchor = fieldInCombinedCrop(fieldRoi);
        // Discard fields whose anchor lies outside the combined ROI (e.g.
        // title/username) — caller will use the per-ROI fallback instead.
        if (anchor.x + anchor.width <= 0 ||
            anchor.y + anchor.height <= 0 ||
            anchor.x >= roi_combined_warped.width ||
            anchor.y >= roi_combined_warped.height)
        {
            return OCRResult{};
        }
        int best = -1;
        double bestScore = 0.0;
        for (size_t i = 0; i < detections.size(); ++i)
        {
            cv::Rect inter = anchor & detections[i].box;
            if (inter.area() <= 0) continue;
            // Score = overlap area / anchor area. Bigger overlap with the
            // anchor wins. Confidence breaks ties.
            double s = (double)inter.area() / (double)std::max(1, anchor.area());
            if (s > bestScore ||
                (s == bestScore && best >= 0 &&
                 detections[i].result.confidence > detections[best].result.confidence))
            {
                bestScore = s;
                best = (int)i;
            }
        }
        if (best < 0) return OCRResult{};
        return detections[best].result;
    };

    ocrResults.score     = pickBestDetection(ROI_Score);
    ocrResults.marvelous = pickBestDetection(ROI_Marvelous);
    ocrResults.perfect   = pickBestDetection(ROI_Perfect);
    ocrResults.great     = pickBestDetection(ROI_Great);
    ocrResults.good      = pickBestDetection(ROI_Good);
    ocrResults.miss      = pickBestDetection(ROI_Miss);
    ocrResults.flare     = pickBestDetection(ROI_Flare);
    ocrResults.max_combo = pickBestDetection(ROI_MaxCombo);

    // ----- Fixed-ROI fallback for numeric fields the detector missed -----
    // When pickBestDetection found no overlapping detection box the result
    // text is empty. Crop the field's anchor rect straight out of warpedImg
    // (same offset/clamp logic as getPreprocessedRoiImage) and run the
    // recogniser directly on it.
    auto fixedRoiFallback = [&](const cv::Rect &ROI_Target,
                                const std::string &fieldName) -> OCRResult {
        if (warpedImg.empty()) return OCRResult{};

        cv::Point2d offset(
            ROI_Target.x - ROI_Details.x,
            ROI_Target.y - ROI_Details.y);

        cv::Rect roi_warped(
            warped_details_top_left.x + offset.x,
            warped_details_top_left.y + offset.y,
            ROI_Target.width,
            ROI_Target.height);

        cv::Rect imgBounds(0, 0, warpedImg.cols, warpedImg.rows);
        roi_warped &= imgBounds;

        if (roi_warped.width <= 0 || roi_warped.height <= 0)
            return OCRResult{};

        cv::Mat crop = warpedImg(roi_warped);
        if (crop.empty())
            return OCRResult{};

        return ocrWrapper.performOCR(crop, OCRType::Digit, fieldName);
    };

    if (ocrResults.score.text.empty())
        ocrResults.score = fixedRoiFallback(ROI_Score, "score");
    if (ocrResults.marvelous.text.empty())
        ocrResults.marvelous = fixedRoiFallback(ROI_Marvelous, "marvelous");
    if (ocrResults.perfect.text.empty())
        ocrResults.perfect = fixedRoiFallback(ROI_Perfect, "perfect");
    if (ocrResults.great.text.empty())
        ocrResults.great = fixedRoiFallback(ROI_Great, "great");
    if (ocrResults.good.text.empty())
        ocrResults.good = fixedRoiFallback(ROI_Good, "good");
    if (ocrResults.miss.text.empty())
        ocrResults.miss = fixedRoiFallback(ROI_Miss, "miss");
    if (ocrResults.flare.text.empty())
        ocrResults.flare = fixedRoiFallback(ROI_Flare, "flare");
    if (ocrResults.max_combo.text.empty())
        ocrResults.max_combo = fixedRoiFallback(ROI_MaxCombo, "max_combo");

    // ----- Outside the combined ROI: per-ROI recogniser-only fallback -----
    // title/username/difficulty/details sit above the score panel.
    ocrResults.title = getPreprocessedRoiImage(
        warpedImg, ROI_Title, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_TITLE), "title", OCRType::EngJP);

    ocrResults.username = getPreprocessedRoiImage(
        warpedImg, ROI_Username, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_USERNAME), "username", OCRType::EngJP);

    ocrResults.difficulty = getPreprocessedRoiImage(
        warpedImg, ROI_Difficulty, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_DIFFICULTY), "difficulty", OCRType::Eng);

    result.ocrResults = ocrResults;

    auto t_total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::high_resolution_clock::now() - t_total_start).count();
    result.totalMs = (int64_t)t_total_ms;
    platform_log("[TIMER] process_image total: %lld ms\n", (long long)t_total_ms);

    return result;
}

// Full pipeline wrapper: phase 1 then (when a badge matched) phase 2. Preserves
// the original single-call behaviour for the picked-image FFI path and offline
// tooling. The live camera session calls detect_details / recognise_details on
// separate threads instead.
ProcessImgResult DdrocrInstance::process_image(cv::Mat inputImg, DetectionSide side,
                                               DebugImageType debugImageType)
{
    DetailsDetectResult det = detect_details(inputImg, side, debugImageType);
    if (!det.matched)
        return det.result;
    return recognise_details(det);
}

OCRResult DdrocrInstance::getPreprocessedRoiImage(
    const cv::Mat &warpedImg,
    const cv::Rect &ROI_Target,
    const cv::Rect &ROI_Details,
    const cv::Point &warped_details_top_left,
    const cv::Point &expand,
    const std::string &imageName,
    const OCRType type)
{
    OCRResult result{}; // Always have a valid return object

    if (warpedImg.empty())
        return result;

    auto t_roi_start = std::chrono::high_resolution_clock::now();

    // Offset for ROI
    cv::Point2d offset(
        ROI_Target.x - ROI_Details.x,
        ROI_Target.y - ROI_Details.y);

    cv::Rect roi_warped(
        warped_details_top_left.x + offset.x,
        warped_details_top_left.y + offset.y,
        ROI_Target.width,
        ROI_Target.height);

    roi_warped = expandRoi(roi_warped, expand);

    cv::Rect imgBounds(0, 0, warpedImg.cols, warpedImg.rows);
    roi_warped &= imgBounds;

    if (roi_warped.width <= 0 || roi_warped.height <= 0)
        return result;

    cv::Mat cropped = warpedImg(roi_warped);

    if (cropped.empty())
        return result;

    // PP-OCRv5 expects natural-color BGR crops matching its training
    // distribution. performOCR handles the canonical resize_norm_img
    // preprocessing internally — pass the raw crop straight through.
    save_img("roi_" + imageName, cropped);

    {
        auto t0 = std::chrono::high_resolution_clock::now();
        result = ocrWrapper.performOCR(cropped, type, imageName);
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::high_resolution_clock::now() - t0).count();
        platform_log("[TIMER] [%s] performOCR: %lld ms\n", imageName.c_str(), (long long)ms);
    }

    platform_log("[OCR] [%s] ROI(%d,%d %dx%d) confidence=%.2f text='%s'\n",
                 imageName.c_str(),
                 roi_warped.x, roi_warped.y,
                 roi_warped.width, roi_warped.height,
                 result.confidence,
                 result.text.c_str());

    auto t_roi_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::high_resolution_clock::now() - t_roi_start).count();
    platform_log("[TIMER] [%s] getPreprocessedRoiImage total: %lld ms\n", imageName.c_str(), (long long)t_roi_ms);

    return result;
}

cv::Rect DdrocrInstance::expandRoi(cv::Rect roi, cv::Point expand)
{
    return cv::Rect(
        roi.x - expand.x,
        roi.y - expand.y,
        roi.width + expand.x * 2,
        roi.height + expand.y * 2);
}

std::vector<cv::Point2f> DdrocrInstance::rectToPoints(const cv::Rect &r)
{
    cv::Point2f tl(r.x, r.y);
    cv::Point2f tr(r.x + r.width, r.y);
    cv::Point2f br(r.x + r.width, r.y + r.height);
    cv::Point2f bl(r.x, r.y + r.height);

    return {tl, tr, br, bl};
}

cv::Rect DdrocrInstance::offsetToRoi(cv::Point tl, cv::Point br, cv::Point expansion)
{
    // Width/height from raw coordinates
    int width = br.x - tl.x;
    int height = br.y - tl.y;

    // Expand ROI by expansion.x and expansion.y on all sides
    int x = tl.x - expansion.x;
    int y = tl.y - expansion.y;
    width += expansion.x * 2;
    height += expansion.y * 2;

    return cv::Rect(x, y, width, height);
}
