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
static const int ROI_IDX_EXSCORE    = 12;


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
                                                   DebugImageType debugImageType,
                                                   cv::Point tapPoint,
                                                   bool strictSide)
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

        // Debug runs live under a debug/ subdir so they don't mix with the
        // app's own documents (e.g. the scores/ proof images).
        const std::string debugRoot = dataPath + "/debug";
        mkdir(debugRoot.c_str(), 0755);
        std::ostringstream oss;
        oss << debugRoot << "/ocr_debug_"
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
    // Per-candidate solo template scores, filled by the side-gate loop below
    // (side != FIRST only). Reused by the wrong-side partner check so it
    // doesn't have to re-run matchTemplate.
    std::vector<float> candScores(detectedRois.size(), -1.0f);
    if (dmatch.index >= 0)
    {
        if (side == DetectionSide::FIRST)
        {
            detectedDetailsIndices.push_back(dmatch.index);
        }
        else
        {
            // Side selection must only choose between the two players' Details
            // badges — but the base minScore also lets visually similar sibling
            // tabs ("Simple results" / "Play Graph" / "FLARE") through, and the
            // leftmost/rightmost of those anchors the homography on the wrong
            // tab. Gate candidates to scores near the best match: the other
            // player's genuine Details badge lands close to the winner, the
            // sibling tabs don't.
            const float sideMin = std::max(
                minScore, dmatch.score * (float)config.details_side_gate_factor);
            for (size_t i = 0; i < detectedRois.size(); ++i)
            {
                std::vector<cv::Rect> one{detectedRois[i]};
                auto m = detailsDetector.classify(inputImg, one, sideMin);
                candScores[i] = m.score; // best score even when below sideMin
                if (m.index == 0)
                {
                    detectedDetailsIndices.push_back((int)i);
                    platform_log("[DETAILS_DET] side candidate %zu score=%.3f (gate %.3f)\n",
                                 i, m.score, sideMin);
                }
            }
            if (detectedDetailsIndices.empty())
                detectedDetailsIndices.push_back(dmatch.index);
        }
    }

    // With LEFT/RIGHT requested but only ONE candidate surviving the gate, the
    // positional pick below degenerates to "best match wins" and the requested
    // side has no influence — selecting 1P can silently lock onto the 2P badge
    // whenever the other player's badge scored under the gate. The two badges
    // sit in the same horizontal band, mirror-separated by several badge
    // widths, so look for the partner among the remaining HSV blobs on the
    // requested side of the survivor:
    //  - a partner that clears the base minScore (only the tighter side gate
    //    filtered it) gets promoted so the positional pick can choose it;
    //  - a band blob that is NOT recognisable as a badge means the requested
    //    side is visible but unreadable this frame — skip the frame rather
    //    than anchor the homography on the wrong player's panel.
    // No band blob on the requested side (single-panel framing) keeps the
    // current best-match behaviour: a lone badge is genuinely ambiguous.
    bool sideRejected = false;
    if (side != DetectionSide::FIRST && detectedDetailsIndices.size() == 1)
    {
        const int chosenIdx = detectedDetailsIndices[0];
        const cv::Rect &chosen = detectedRois[chosenIdx];
        const float cx = chosen.x + chosen.width * 0.5f;
        const float cy = chosen.y + chosen.height * 0.5f;
        const bool wantLeft = (side == DetectionSide::LEFT);
        // Minimum centre-to-centre distance (in badge widths) for a blob to be
        // the other panel's badge rather than an adjacent sibling tab. The
        // real pair sits ~4 badge widths apart in the reference layout.
        const float minPartnerDist = 2.5f * (float)chosen.width;
        int   bestPartner = -1;
        float bestPartnerScore = -1.0f;
        bool  bandBlobOnWantedSide = false;
        for (size_t i = 0; i < detectedRois.size(); ++i)
        {
            if ((int)i == chosenIdx) continue;
            const cv::Rect &r = detectedRois[i];
            const float rx = r.x + r.width * 0.5f;
            const float ry = r.y + r.height * 0.5f;
            if (wantLeft ? (rx >= cx) : (rx <= cx)) continue;
            // Same tab-row band and comparable size as the surviving badge.
            if (std::abs(ry - cy) > (float)chosen.height) continue;
            if (r.height * 2 < chosen.height || r.height > chosen.height * 2) continue;
            if (r.width * 2 < chosen.width || r.width > chosen.width * 2) continue;
            if (std::abs(rx - cx) < minPartnerDist) continue;
            bandBlobOnWantedSide = true;
            if (candScores[i] >= minScore && candScores[i] > bestPartnerScore)
            {
                bestPartnerScore = candScores[i];
                bestPartner = (int)i;
            }
        }
        if (bestPartner >= 0)
        {
            detectedDetailsIndices.push_back(bestPartner);
            platform_log("[DETAILS_DET] promoted %s-side partner %d score=%.3f "
                         "(under side gate, over minScore %.2f)\n",
                         wantLeft ? "left" : "right", bestPartner,
                         bestPartnerScore, minScore);
        }
        else if (bandBlobOnWantedSide && strictSide)
        {
            sideRejected = true;
            platform_log("[DETAILS_DET] requested %s side has a band blob but no "
                         "recognisable badge — skipping frame instead of using "
                         "wrong-side badge %d\n",
                         wantLeft ? "left" : "right", chosenIdx);
        }
        else if (bandBlobOnWantedSide)
        {
            // One-shot caller: no next frame to wait for, so keep the best
            // match auto-selected and let the user tap-correct it.
            platform_log("[DETAILS_DET] requested %s side unreadable — one-shot "
                         "caller, falling back to badge %d\n",
                         wantLeft ? "left" : "right", chosenIdx);
        }
    }

    // Manual override: the user tapped a candidate box on the live preview. A
    // tap is authoritative — it bypasses the template gate and the side
    // heuristics entirely (the homography only needs the blob's contour, not
    // its match score). The point is in processed-frame pixels and persists
    // across frames, so it keeps selecting whatever candidate contains it; if
    // the framing drifts and no box contains it any more, the heuristics above
    // stay in charge.
    if (tapPoint.x >= 0 && tapPoint.y >= 0)
    {
        int    tapIdx = -1;
        double tapDist = 0;
        for (size_t i = 0; i < detectedRois.size(); ++i)
        {
            const cv::Rect &r = detectedRois[i];
            // Inflate a little so taps just outside a thin box still count.
            const int mx = r.width / 4, my = r.height / 4;
            const cv::Rect hit(r.x - mx, r.y - my,
                               r.width + 2 * mx, r.height + 2 * my);
            if (!hit.contains(tapPoint)) continue;
            const double dx = r.x + r.width * 0.5 - tapPoint.x;
            const double dy = r.y + r.height * 0.5 - tapPoint.y;
            const double dist = dx * dx + dy * dy;
            if (tapIdx < 0 || dist < tapDist)
            {
                tapIdx = (int)i;
                tapDist = dist;
            }
        }
        if (tapIdx >= 0)
        {
            detectedDetailsIndices.assign(1, tapIdx);
            sideRejected = false;
            platform_log("[DETAILS_DET] tap override (%d,%d) -> candidate %d\n",
                         tapPoint.x, tapPoint.y, tapIdx);
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

    if (detectedDetailsIndices.empty() || sideRejected)
    {
        auto t_total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::high_resolution_clock::now() - t_total_start).count();
        platform_log("[TIMER] process_image total (no Details found): %lld ms\n", (long long)t_total_ms);
        if (sideRejected)
            platform_log("Details badge only found on the wrong side (score=%.3f). Skipping frame.\n", dmatch.score);
        else
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
    cv::Rect ROI_ExScore    = roiRect(ROI_IDX_EXSCORE);

    // Calibration is anchored on the P2 (right) panel's badge. Fields inside
    // the player's own score panel keep the same badge-relative offset on both
    // sides, but fields that don't travel with the badge — the screen-centred
    // title and the per-player top-bar username/difficulty plate — need their
    // P2 offsets reflected about the badge when P1 is the anchor. With the
    // P1/P2 badges mirror-symmetric about the screen centreline, the
    // centreline cancels out and no extra calibration is needed:
    // newX1 = detailsX2 - (x2 - detailsX1).
    if (side == DetectionSide::LEFT)
    {
        auto mirrorAboutBadge = [&](cv::Rect &r) {
            r.x = 2 * ROI_Details.x + ROI_Details.width - r.x - r.width;
        };
        mirrorAboutBadge(ROI_Title);
        // The top-bar plate is position-mirrored between P1 and P2, but its
        // content is laid out identically on both sides (left-aligned), so a
        // pure rect mirror lands right-aligned within the P1 plate — e.g. the
        // difficulty crop catches "…STYLE Challen" instead of "Challenge 14".
        // Mirror the plate box, then re-place each field at its original
        // offset within the plate. Plate x-bounds are username_detection_box
        // from the reference table in lib/ocr_config.dart.
        const int plateX1 = 1616, plateX2 = 2093;
        cv::Rect plate(plateX1, 0, plateX2 - plateX1, 1);
        mirrorAboutBadge(plate);
        ROI_Username.x   = plate.x + (ROI_Username.x - plateX1);
        ROI_Difficulty.x = plate.x + (ROI_Difficulty.x - plateX1);
    }

    // Using regionprops Convex hull method (det.chosenHull is the contour the
    // detector picked for the matched Details ROI).
    std::vector<cv::Point> hull;
    cv::convexHull(det.chosenHull, hull);

    if (hull.size() < 4)
    {
        platform_log("Not enough points for homography, defaulting to first detected ROI\n");
        result.isDetected = 1;
        return result;
    }

    // Corner extraction, robust to camera roll. Picking extreme points in
    // image axes (min/max of x+y and x−y) silently mis-assigns corners once
    // the badge is rotated — handheld camera frames roll freely, which is why
    // the picked-image path (roughly upright photos) worked while the live
    // camera warped wildly. De-rotate the hull by the badge's dominant
    // orientation (minAreaRect long side), take the four extremes there, then
    // map back to the original points. Assumes |roll| < 90° (the badge still
    // appears wider than tall), which the portrait-rotated camera guarantees.
    cv::RotatedRect rr = cv::minAreaRect(hull);
    float longAngle =
        (rr.size.width >= rr.size.height) ? rr.angle : rr.angle + 90.0f;
    // minAreaRect's angle only defines the long-side direction modulo 180°
    // (an axis-aligned wide rect commonly reports angle=90 with width/height
    // swapped, making longAngle 180). Normalise into (-90, 90] — a 180°
    // de-rotation would swap tl<->br and flip the entire warp upside down.
    while (longAngle > 90.0f) longAngle -= 180.0f;
    while (longAngle <= -90.0f) longAngle += 180.0f;
    const float rad = longAngle * (float)CV_PI / 180.0f;
    const float ca = std::cos(rad), sa = std::sin(rad);

    std::vector<cv::Point2f> flat(hull.size());
    for (size_t i = 0; i < hull.size(); ++i)
    {
        float dx = (float)hull[i].x - rr.center.x;
        float dy = (float)hull[i].y - rr.center.y;
        flat[i] = cv::Point2f(dx * ca + dy * sa, -dx * sa + dy * ca);
    }

    size_t tlI = 0, brI = 0, trI = 0, blI = 0;
    for (size_t i = 1; i < flat.size(); ++i)
    {
        if (flat[i].x + flat[i].y < flat[tlI].x + flat[tlI].y) tlI = i;
        if (flat[i].x + flat[i].y > flat[brI].x + flat[brI].y) brI = i;
        if (flat[i].x - flat[i].y > flat[trI].x - flat[trI].y) trI = i;
        if (flat[i].x - flat[i].y < flat[blI].x - flat[blI].y) blI = i;
    }
    cv::Point2f tl(hull[tlI]), tr(hull[trI]), br(hull[brI]), bl(hull[blI]);

    cv::Mat approx_img = inputImg.clone();
    for (size_t i = 0; i < hull.size(); i++)
        cv::line(approx_img, hull[i], hull[(i + 1) % hull.size()],
                 cv::Scalar(0, 255, 0), 4);
    for (const cv::Point2f &p : {tl, tr, br, bl})
        cv::circle(approx_img, p, 12, cv::Scalar(0, 255, 255), -1);
    save_img("extrema", approx_img);

    // Reject frames whose corner quad doesn't actually describe the hull
    // (blob merged with a neighbouring UI element, motion-blur smear, or a
    // degenerate/repeated corner): a clean badge blob is a convex quad, so
    // the corner quad should cover nearly all of the hull's area. A garbage
    // quad here becomes a garbage homography and wrecks every ROI downstream —
    // better to skip this frame and let the aggregator wait for a clean one.
    const double hullArea = cv::contourArea(hull);
    const double quadArea =
        cv::contourArea(std::vector<cv::Point2f>{tl, tr, br, bl});
    if (hullArea <= 0.0 ||
        quadArea / hullArea < config.homography_min_quad_coverage)
    {
        platform_log("Corner quad covers %.0f%% of hull — rejecting frame for homography\n",
                     hullArea > 0.0 ? quadArea / hullArea * 100.0 : 0.0);
        result.isDetected = 1;
        return result;
    }

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
                {"ex_score",  fieldInCombinedCrop(ROI_ExScore)},
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

    // Returns the index into `detections` of the best box for the field, or -1.
    auto pickBestDetectionIdx = [&](const cv::Rect &fieldRoi) -> int {
        cv::Rect anchor = fieldInCombinedCrop(fieldRoi);
        // Discard fields whose anchor lies outside the combined ROI (e.g.
        // title/username) — caller will use the per-ROI fallback instead.
        if (anchor.x + anchor.width <= 0 ||
            anchor.y + anchor.height <= 0 ||
            anchor.x >= roi_combined_warped.width ||
            anchor.y >= roi_combined_warped.height)
        {
            return -1;
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
        return best;
    };

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

    // Combined-panel fields: pick a det box by anchor overlap, else fall back
    // to a fixed-ROI recognise. detIdx records which det box supplied the
    // result (-1 = fallback or nothing) for the debug panel.
    struct CombinedField { const char *name; const cv::Rect *roi; OCRResult *res; int detIdx; };
    CombinedField combinedFields[] = {
        {"score",     &ROI_Score,     &ocrResults.score,     -1},
        {"marvelous", &ROI_Marvelous, &ocrResults.marvelous, -1},
        {"perfect",   &ROI_Perfect,   &ocrResults.perfect,   -1},
        {"great",     &ROI_Great,     &ocrResults.great,     -1},
        {"good",      &ROI_Good,      &ocrResults.good,      -1},
        {"miss",      &ROI_Miss,      &ocrResults.miss,      -1},
        {"flare",     &ROI_Flare,     &ocrResults.flare,     -1},
        {"max_combo", &ROI_MaxCombo,  &ocrResults.max_combo, -1},
        {"ex_score",  &ROI_ExScore,   &ocrResults.ex_score,  -1},
    };
    for (auto &f : combinedFields)
    {
        f.detIdx = pickBestDetectionIdx(*f.roi);
        if (f.detIdx >= 0)
            *f.res = detections[f.detIdx].result;
        if (f.res->text.empty())
        {
            *f.res = fixedRoiFallback(*f.roi, f.name);
            f.detIdx = -1;
        }
    }

    // The digit recogniser keeps '/' so max_combo's "combo/total note count"
    // reading can be split here: keep only the combo. Any stray slash in the
    // other numeric fields is OCR noise — drop it.
    for (auto &f : combinedFields)
    {
        std::string &t = f.res->text;
        size_t slash = t.find('/');
        if (slash == std::string::npos)
            continue;
        if (std::strcmp(f.name, "max_combo") == 0)
            t.resize(slash);
        else
            t.erase(std::remove(t.begin(), t.end(), '/'), t.end());
    }

    // The game renders EX score without thousands separators (unlike the
    // money score), so any comma the recogniser emits there is OCR noise.
    {
        std::string &t = ocrResults.ex_score.text;
        t.erase(std::remove(t.begin(), t.end(), ','), t.end());
    }

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

    // Debug ON: render ONE composite debug image — the single point of
    // reference for what the pipeline did on this frame.
    //   Left:  the warped frame, cropped to the warp's filled content and
    //          downscaled, carrying geometry only (no result text on pixels):
    //            green   - per-field OCR ROIs, labelled with the field key
    //            cyan    - per-field anchor rects the det picker matches against
    //            yellow  - the combined ROI fed to PaddleOCR detection
    //            magenta - det boxes, numbered #n (text lives in the panel)
    //            red dot - the warped Details anchor
    //   Right: a rec panel — per field: which det box (or fallback path)
    //          supplied the result, confidence, the recognised text, and the
    //          LITERAL 48px crop the rec model consumed; then every det box's
    //          #n -> text/confidence.
    // Stored on result.debugOverlay (shown in-app) and, when a disk debug dir
    // exists, also written as roi_overlay.png.
    if (debugImageType == DebugImageType::ON && !warpedImg.empty())
    {
        cv::Mat overlay;
        if (warpedImg.channels() == 1)
            cv::cvtColor(warpedImg, overlay, cv::COLOR_GRAY2BGR);
        else
            overlay = warpedImg.clone();

        const cv::Rect overlayBounds(0, 0, overlay.cols, overlay.rows);

        // Content rect first (bounding box of the source frame's corners pushed
        // through H): the canvas is 4000x5000 but only this region holds pixels.
        // Knowing the final downscale up-front lets fonts/line widths be drawn
        // at full res yet stay legible after the resize to kImgH.
        cv::Rect content = overlayBounds;
        {
            std::vector<cv::Point2f> srcCorners = {
                {0.f, 0.f},
                {(float)inputImg.cols, 0.f},
                {(float)inputImg.cols, (float)inputImg.rows},
                {0.f, (float)inputImg.rows}};
            std::vector<cv::Point2f> warpedCorners;
            cv::perspectiveTransform(srcCorners, warpedCorners, H);
            cv::Rect bb = cv::boundingRect(warpedCorners);
            const int margin = 30;
            bb.x -= margin; bb.y -= margin;
            bb.width += margin * 2; bb.height += margin * 2;
            cv::Rect clipped = bb & overlayBounds;
            if (clipped.width > 0 && clipped.height > 0)
                content = clipped;
        }

        const int kImgH = 1400;
        const double shrink = (double)kImgH / std::max(1, content.height);
        const double fs = 0.7 / shrink;                                // font scale
        const int th = std::max(2, (int)std::round(2.0 / shrink));     // line thickness

        auto warpField = [&](const cv::Rect &fieldRoi) -> cv::Rect {
            return cv::Rect(
                warped_details_top_left.x + (fieldRoi.x - ROI_Details.x),
                warped_details_top_left.y + (fieldRoi.y - ROI_Details.y),
                fieldRoi.width, fieldRoi.height);
        };

        // Thin cyan anchor rect (what the det picker matches against), then
        // the green expanded OCR ROI with the field key only.
        auto drawField = [&](const cv::Rect &fieldRoi, int idx,
                             const std::string &name) {
            cv::Rect anchor = warpField(fieldRoi) & overlayBounds;
            if (anchor.width > 0 && anchor.height > 0)
                cv::rectangle(overlay, anchor, cv::Scalar(255, 255, 0), th / 2 + 1);
            cv::Rect r = expandRoi(warpField(fieldRoi), expand(idx)) & overlayBounds;
            if (r.width <= 0 || r.height <= 0) return;
            cv::rectangle(overlay, r, cv::Scalar(0, 255, 0), th);
            cv::putText(overlay, name, cv::Point(r.x + 4, r.y - 8),
                        cv::FONT_HERSHEY_SIMPLEX, fs, cv::Scalar(0, 255, 0), th,
                        cv::LINE_AA);
        };

        drawField(ROI_Details,    ROI_IDX_DETAILS,    "details");
        drawField(ROI_Score,      ROI_IDX_SCORE,      "score");
        drawField(ROI_Marvelous,  ROI_IDX_MARVELOUS,  "marvelous");
        drawField(ROI_Perfect,    ROI_IDX_PERFECT,    "perfect");
        drawField(ROI_Great,      ROI_IDX_GREAT,      "great");
        drawField(ROI_Good,       ROI_IDX_GOOD,       "good");
        drawField(ROI_Miss,       ROI_IDX_MISS,       "miss");
        drawField(ROI_Flare,      ROI_IDX_FLARE,      "flare");
        drawField(ROI_MaxCombo,   ROI_IDX_MAXCOMBO,   "max_combo");
        drawField(ROI_ExScore,    ROI_IDX_EXSCORE,    "ex_score");
        drawField(ROI_Title,      ROI_IDX_TITLE,      "title");
        drawField(ROI_Username,   ROI_IDX_USERNAME,   "username");
        drawField(ROI_Difficulty, ROI_IDX_DIFFICULTY, "difficulty");

        // Only the det boxes a field actually consumed — the rest (stray
        // detections the picker never matched) are noise for this view and
        // stay visible in paddle_detect.png if ever needed.
        std::vector<bool> detChosen(detections.size(), false);
        for (const auto &f : combinedFields)
            if (f.detIdx >= 0) detChosen[f.detIdx] = true;

        // Chosen det boxes: numbered on the image; recognised text lives in
        // the panel so nothing overlaps the pixels being debugged.
        for (size_t i = 0; i < detections.size(); ++i)
        {
            if (!detChosen[i]) continue;
            cv::Rect box(detections[i].box.x + roi_combined_warped.x,
                         detections[i].box.y + roi_combined_warped.y,
                         detections[i].box.width, detections[i].box.height);
            box &= overlayBounds;
            if (box.width <= 0 || box.height <= 0) continue;
            cv::rectangle(overlay, box, cv::Scalar(255, 0, 255), th);
            char lbl[16];
            snprintf(lbl, sizeof(lbl), "#%zu", i);
            cv::putText(overlay, lbl, cv::Point(box.x, box.y - 6),
                        cv::FONT_HERSHEY_SIMPLEX, fs, cv::Scalar(255, 0, 255), th,
                        cv::LINE_AA);
        }

        // Combined ROI outline (yellow) and the Details anchor point (red).
        cv::Rect combinedOutline = roi_combined_warped & overlayBounds;
        if (combinedOutline.width > 0 && combinedOutline.height > 0)
            cv::rectangle(overlay, combinedOutline, cv::Scalar(0, 255, 255), th);
        cv::circle(overlay, warped_details_top_left,
                   std::max(6, (int)std::round(6.0 / shrink)), cv::Scalar(0, 0, 255), -1);

        cv::Mat left;
        int leftW = std::max(1, (int)std::round(content.width * shrink));
        cv::resize(overlay(content), left, cv::Size(leftW, kImgH), 0, 0,
                   cv::INTER_AREA);

        // ----- Rec panel -----
        struct PanelRow { std::string label; std::string text; cv::Mat strip; cv::Scalar color; };
        std::vector<PanelRow> rows;
        auto addRow = [&](const char *name, const OCRResult &res, int detIdx,
                          bool inCombined) {
            char lbl[128];
            cv::Scalar color;
            if (detIdx >= 0)
            {
                snprintf(lbl, sizeof(lbl), "%s <- det #%d (%.2f)", name, detIdx,
                         res.confidence);
                color = cv::Scalar(0, 255, 0);
            }
            else if (inCombined)
            {
                snprintf(lbl, sizeof(lbl), "%s <- fixed-ROI fallback (%.2f)", name,
                         res.confidence);
                color = cv::Scalar(0, 255, 255);
            }
            else
            {
                snprintf(lbl, sizeof(lbl), "%s <- rec-only crop (%.2f)", name,
                         res.confidence);
                color = cv::Scalar(255, 255, 0);
            }
            rows.push_back({lbl, res.text.empty() ? "(empty)" : res.text,
                            res.recInput, color});
        };
        for (const auto &f : combinedFields)
            addRow(f.name, *f.res, f.detIdx, true);
        addRow("title",      ocrResults.title,      -1, false);
        addRow("username",   ocrResults.username,   -1, false);
        addRow("difficulty", ocrResults.difficulty, -1, false);

        const int panelW = 760, pad = 12;
        const int stripMaxW = panelW - 2 * pad - 8;

        // Measure the panel so the canvas is tall enough for every row (the
        // draw loop below MUST mirror these increments).
        int need = pad + 20 + 20; // section header + legend line
        for (const auto &r : rows)
        {
            need += 22 + 26 + 12;
            if (!r.strip.empty())
            {
                int sw = std::min(stripMaxW, r.strip.cols);
                need += (int)std::round((double)r.strip.rows * sw /
                                        std::max(1, r.strip.cols)) + 6;
            }
        }
        int chosenCount = 0;
        for (size_t i = 0; i < detChosen.size(); ++i)
            if (detChosen[i]) chosenCount++;
        need += 24 + 20 + chosenCount * 22 + pad;

        const int canvasH = std::max(kImgH, need);
        cv::Mat canvas(canvasH, left.cols + panelW, CV_8UC3, cv::Scalar(0, 0, 0));
        left.copyTo(canvas(cv::Rect(0, 0, left.cols, left.rows)));

        const int x0 = left.cols + pad;
        int y = pad + 14;
        cv::putText(canvas, "rec (what the model actually read)",
                    cv::Point(x0, y), cv::FONT_HERSHEY_SIMPLEX, 0.55,
                    cv::Scalar(255, 255, 255), 1, cv::LINE_AA);
        y += 20;
        cv::putText(canvas,
                    "green=ROI cyan=anchor yellow=combined magenta=det red=anchor",
                    cv::Point(x0, y), cv::FONT_HERSHEY_SIMPLEX, 0.4,
                    cv::Scalar(160, 160, 160), 1, cv::LINE_AA);
        for (const auto &r : rows)
        {
            y += 22;
            cv::putText(canvas, r.label, cv::Point(x0, y),
                        cv::FONT_HERSHEY_SIMPLEX, 0.5, r.color, 1, cv::LINE_AA);
            y += 26;
            cv::putText(canvas, r.text, cv::Point(x0 + 8, y),
                        cv::FONT_HERSHEY_SIMPLEX, 0.65, cv::Scalar(255, 255, 255),
                        1, cv::LINE_AA);
            if (!r.strip.empty())
            {
                int sw = std::min(stripMaxW, r.strip.cols);
                int sh = (int)std::round((double)r.strip.rows * sw /
                                         std::max(1, r.strip.cols));
                cv::Mat strip;
                cv::resize(r.strip, strip, cv::Size(sw, sh));
                if (strip.channels() == 1)
                    cv::cvtColor(strip, strip, cv::COLOR_GRAY2BGR);
                y += 6;
                if (y + sh <= canvasH)
                    strip.copyTo(canvas(cv::Rect(x0 + 8, y, sw, sh)));
                y += sh;
            }
            y += 12;
        }
        y += 24;
        cv::putText(canvas, "chosen det boxes (magenta #n)", cv::Point(x0, y),
                    cv::FONT_HERSHEY_SIMPLEX, 0.55, cv::Scalar(255, 255, 255), 1,
                    cv::LINE_AA);
        y += 20;
        for (size_t i = 0; i < detections.size(); ++i)
        {
            if (!detChosen[i]) continue;
            y += 22;
            if (y >= canvasH - pad) break;
            char lbl[160];
            snprintf(lbl, sizeof(lbl), "#%zu '%s' (%.2f)", i,
                     detections[i].result.text.c_str(),
                     detections[i].result.confidence);
            cv::putText(canvas, lbl, cv::Point(x0, y), cv::FONT_HERSHEY_SIMPLEX,
                        0.5, cv::Scalar(255, 0, 255), 1, cv::LINE_AA);
        }

        result.debugOverlay = canvas;

        if (!debugDir.empty())
        {
            char path[512];
            snprintf(path, sizeof(path), "%s/roi_overlay.png", debugDir.c_str());
            cv::imwrite(path, result.debugOverlay);
            platform_log("wrote: %s (debug overlay, %dx%d)\n", path,
                         canvas.cols, canvas.rows);
        }
    }

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
                                               DebugImageType debugImageType,
                                               cv::Point tapPoint,
                                               bool strictSide)
{
    DetailsDetectResult det =
        detect_details(inputImg, side, debugImageType, tapPoint, strictSide);
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
