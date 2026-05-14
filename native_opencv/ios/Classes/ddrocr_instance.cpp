#include "ddrocr_instance.h"
#include <chrono>
#include <cstring>
#include <algorithm>
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

DdrocrInstance::DdrocrInstance(std::string dataPath)
    : dataPath(dataPath), ocrWrapper(dataPath)
{
    platform_log("DdrocrInstance initialized\n");
}

DdrocrInstance::~DdrocrInstance()
{
    platform_log("DdrocrInstance destroyed\n");
}

void DdrocrInstance::setConfig(const COCRConfig &cfg)
{
    config = cfg;
    ocrWrapper.psm_eng   = cfg.psm_eng;
    ocrWrapper.psm_engjp = cfg.psm_engjp;
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

ProcessImgResult DdrocrInstance::process_image(cv::Mat inputImg, DetectionSide side)
{
    ProcessImgResult result;

    // Create a timestamped directory for all debug images from this run
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
        ocrWrapper.debugDir = debugDir;
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

    cv::Mat grayImg;
    cv::cvtColor(inputImg, grayImg, cv::COLOR_BGR2GRAY);

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
        return result;
    }

    // Preprocess image for OCR on details
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(31, 31));
    cv::Mat closed, Icorrected;
    cv::morphologyEx(inputImg, closed, cv::MORPH_CLOSE, kernel);
    cv::subtract(closed, inputImg, Icorrected);

    // gaussian filter sigma=1
    cv::Mat Ifiltered;
    cv::GaussianBlur(Icorrected, Ifiltered, cv::Size(0, 0), 1.0);

    // rgb2gray
    cv::Mat preprocessed_BW;
    cv::cvtColor(Ifiltered, preprocessed_BW, cv::COLOR_BGR2GRAY);

    // MATLAB-like imbinarize (Otsu) -> logical 0/1
    cv::Mat preprocessed_BW1;
    preprocessed_BW1 = otsuToLogical(preprocessed_BW);

    // TODO: this takes 4000ms, move this noise reduction to before logical 
    // bwareaopen - remove connected components smaller than 5 pixels
    // cv::Mat preprocessed_BW2 = preprocessed_BW1.clone();
    // std::vector<std::vector<cv::Point>> preprocessed_contours;
    // cv::Mat labels, stats, centroids;
    // int preprocessed_n = cv::connectedComponentsWithStats(preprocessed_BW1, labels, stats, centroids);
    // for (int i = 1; i < preprocessed_n; i++)
    // {
    //     if (stats.at<int>(i, cv::CC_STAT_AREA) < 5)
    //     {
    //         cv::Mat mask = (labels == i);
    //         preprocessed_BW2.setTo(0, mask);
    //     }
    // }

    // imcomplement for logical image (0/1)
    cv::Mat preprocessed_BW3;
    cv::subtract(cv::Scalar::all(1), preprocessed_BW1, preprocessed_BW3);

    checkpoint("image preprocessing (close/gaussian/otsu/bwareaopen)", t_rolling_timer);

    cv::Mat roi_img = inputImg.clone();
    int correct_roi_idx = -1;
    std::vector<int> detectedDetailsIndices;

    // Create a details_rois subfolder for debug output
    std::string detailsRoiDir;
    if (!debugDir.empty())
    {
        detailsRoiDir = debugDir + "/details_rois";
        mkdir(detailsRoiDir.c_str(), 0755);
    }

    for (size_t i = 0; i < detectedRois.size(); i++)
    {
        cv::rectangle(roi_img, detectedRois[i], cv::Scalar(0, 255, 0), 4);
         cv::Rect details_roi = detectedRois[i];

        save_img("preprocessed_BW3", logicalToDisplayU8(preprocessed_BW3));

        cv::Mat roiMat = preprocessed_BW3(details_roi);
        OCRResult roiOcrResult = {};

        // Upscale + pad the "Details" ROI before OCR — matches the
        // preprocessing that getPreprocessedRoiImage applies to score ROIs.
        cv::Mat detailsInput;
        cv::resize(roiMat, detailsInput, cv::Size(), 3.0, 3.0, cv::INTER_NEAREST);
        cv::copyMakeBorder(detailsInput, detailsInput,
                           0, 0, 0, 0,
                           cv::BORDER_CONSTANT, cv::Scalar(1));

        // Save raw and preprocessed details ROI candidates to debug subfolder
        if (!detailsRoiDir.empty())
        {
            char rawPath[512], prepPath[512];
            snprintf(rawPath, sizeof(rawPath), "%s/roi_%zu_raw.png",
                     detailsRoiDir.c_str(), i);
            snprintf(prepPath, sizeof(prepPath), "%s/roi_%zu_preprocessed.png",
                     detailsRoiDir.c_str(), i);
            cv::imwrite(std::string(rawPath), logicalToDisplayU8(roiMat));
            cv::imwrite(std::string(prepPath), logicalToDisplayU8(detailsInput));
            platform_log("[DEBUG] saved details ROI %zu: %s\n", i, rawPath);
        }

        auto t_ocr_start = std::chrono::high_resolution_clock::now();
        roiOcrResult = ocrWrapper.performOCR(detailsInput.clone(), OCRType::Details);
        // roiOcrResult = ocrWrapper.performOCR(detailsInput.clone());
        auto t_ocr_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::high_resolution_clock::now() - t_ocr_start).count();
        platform_log("[TIMER] performOCR ROI %zu: %lld ms\n", i, (long long)t_ocr_ms);
        // TODO: fix Tesseract's confidence calibration to reliably use this threshold
        //        if (roiOcrResult.confidence < 0.5)
        //        {
        //            platform_log("Low OCR confidence (%.2f) for ROI %d, skipping\n", roiOcrResult.confidence, i);
        //            continue;
        //        }

        // Strip all non-alphanumeric characters
        std::string cleanText;
        for (char c : roiOcrResult.text)
        {
            if (std::isalnum(static_cast<unsigned char>(c)))
                cleanText += std::tolower(static_cast<unsigned char>(c));
        }
        // Normalize target string: "Details" -> "details"
        const std::string target = "details";
        // Check if cleanText contains target as a substring (loose match)
        if (cleanText.find(target) != std::string::npos)
        {
            detectedDetailsIndices.push_back(i);
            platform_log("Found 'Details' (loose match) with confidence %.2f in ROI %d\n", roiOcrResult.confidence, i);
        }
    }

    checkpoint("details OCR loop", t_rolling_timer);

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
        platform_log("Failed to find 'Details' in any ROI, defaulting to first detected ROI\n");
        result.detailsRoiIndex = -1;
        return result;
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
        // FIRST: use the first OCR match found
        correct_roi_idx = detectedDetailsIndices[0];
    }
    result.detailsRoiIndex = correct_roi_idx;

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

    if (result.rois.size() <= correct_roi_idx)
    {
        platform_log("Not enough ROIs detected, defaulting to first detected ROI\n");
        result.isDetected = 1;
        return result;
    }

    // Using regionprops Convex hull method
    std::vector<cv::Point> hull;
    cv::convexHull(contours_final[correct_roi_idx], hull);

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

    ocrResults.score = getPreprocessedRoiImage(
        warpedImg, ROI_Score, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_SCORE), "score", OCRType::Digit);

    ocrResults.marvelous = getPreprocessedRoiImage(
        warpedImg, ROI_Marvelous, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_MARVELOUS), "marvelous", OCRType::Digit);

    ocrResults.perfect = getPreprocessedRoiImage(
        warpedImg, ROI_Perfect, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_PERFECT), "perfect", OCRType::Digit);

    ocrResults.great = getPreprocessedRoiImage(
        warpedImg, ROI_Great, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_GREAT), "great", OCRType::Digit);

    ocrResults.good = getPreprocessedRoiImage(
        warpedImg, ROI_Good, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_GOOD), "good", OCRType::Digit);

    ocrResults.miss = getPreprocessedRoiImage(
        warpedImg, ROI_Miss, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_MISS), "miss", OCRType::Digit);

    ocrResults.flare = getPreprocessedRoiImage(
        warpedImg, ROI_Flare, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_FLARE), "flare", OCRType::Eng);

    ocrResults.title = getPreprocessedRoiImage(
        warpedImg, ROI_Title, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_TITLE), "title", OCRType::EngJP);

    ocrResults.username = getPreprocessedRoiImage(
        warpedImg, ROI_Username, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_USERNAME), "username", OCRType::EngJP);

    ocrResults.difficulty = getPreprocessedRoiImage(
        warpedImg, ROI_Difficulty, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_DIFFICULTY), "difficulty", OCRType::Eng);

    ocrResults.max_combo = getPreprocessedRoiImage(
        warpedImg, ROI_MaxCombo, ROI_Details, warped_details_top_left,
        expand(ROI_IDX_MAXCOMBO), "max_combo", OCRType::Digit);

    result.ocrResults = ocrResults;

    auto t_total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::high_resolution_clock::now() - t_total_start).count();
    platform_log("[TIMER] process_image total: %lld ms\n", (long long)t_total_ms);

    return result;
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

    // Step 1: Upscale ROI 4× before binarization (tiny ~50px ROIs → ~200px)
    cv::Mat upscaled;
    cv::resize(cropped, upscaled, cv::Size(), config.resolution_scale, config.resolution_scale, cv::INTER_CUBIC);

    // Preprocessing: top-hat + grayscale + threshold
    // Kernel scaled proportionally: 31×31 → 125×125 for 4× upscale
    cv::Mat kernel_tophat = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(config.tophat_kernel_size, config.tophat_kernel_size));

    cv::Mat corrected;
    cv::morphologyEx(upscaled, corrected, cv::MORPH_TOPHAT, kernel_tophat);

    cv::Mat gray;
    cv::cvtColor(corrected, gray, cv::COLOR_BGR2GRAY);

    // Step 2: Light GaussianBlur to denoise before Otsu
    cv::GaussianBlur(gray, gray, cv::Size(config.gaussian_blur_size, config.gaussian_blur_size), 0);

    cv::Mat BW2;

    // Tesseract: use logical 0/1 binary image.
    cv::Mat BW1 = otsuToLogical(gray);
    cv::subtract(cv::Scalar::all(1), BW1, BW2);
    // In BW2: text=1 (foreground), background=0

    // Add white border padding so Tesseract sees whitespace around text.
    // In BW2 after complement: text=0, background=1. Pad with 1 (background/white).
    cv::copyMakeBorder(BW2, BW2, config.border, config.border, config.border, config.border,
                       cv::BORDER_CONSTANT, cv::Scalar(1));

    result = ocrWrapper.performOCR(BW2.clone(), type, imageName);

    platform_log("[OCR] [%s] ROI(%d,%d %dx%d) confidence=%.2f text='%s'\n",
                 imageName.c_str(),
                 roi_warped.x, roi_warped.y,
                 roi_warped.width, roi_warped.height,
                 result.confidence,
                 result.text.c_str());

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
