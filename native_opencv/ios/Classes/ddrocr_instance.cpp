#include "ddrocr_instance.h"
#include <chrono>
#include <cstring>
#include <algorithm>

#ifdef __ANDROID__
#include <android/log.h>
#endif

const int max_value_H = 360 / 2;
const int max_value = 255;

extern void platform_log(const char *fmt, ...);

DdrocrInstance::DdrocrInstance(std::string dataPath)
    : ocrWrapper(dataPath)
{
    platform_log("DdrocrInstance initialized\n");
}

DdrocrInstance::~DdrocrInstance()
{
    platform_log("DdrocrInstance destroyed\n");
}

ProcessImgResult DdrocrInstance::process_image(cv::Mat inputImg, const std::string &outputImgPath)
{
    ProcessImgResult result;

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

    // Do blob detection and filter small blobs
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(BW_HSV, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    cv::Mat BW2 = cv::Mat::zeros(BW_HSV.size(), CV_8U);
    for (size_t i = 0; i < contours.size(); i++)
    {
        double area = cv::contourArea(contours[i]);
        if (area >= 3000 && area <= 50000)
        {
            cv::drawContours(BW2, contours, i, cv::Scalar(255), cv::FILLED);
        }
    }

    int m = 360;
    int n = 90;

    // Create opening kernel using byte array (faster than getStructuringElement)
    int open_width = m * 0.1;
    int open_height = n * 0.1;
    uchar *open_data = new uchar[open_height * open_width];
    memset(open_data, 255, open_height * open_width);
    cv::Mat SE_open(open_height, open_width, CV_8U, open_data);

    auto start_open = std::chrono::high_resolution_clock::now();
    cv::Mat BW3;
    cv::morphologyEx(BW2, BW3, cv::MORPH_OPEN, SE_open);
    save_img(outputImgPath, "BW_HSV", BW_HSV);
    save_img(outputImgPath, "BW2", BW2);
    save_img(outputImgPath, "BW3", BW3);
    auto end_open = std::chrono::high_resolution_clock::now();
    auto duration_open = std::chrono::duration_cast<std::chrono::microseconds>(end_open - start_open);
    std::cout << "Opening operation with byte array kernel: " << duration_open.count() << " microseconds" << std::endl;

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

    // imbinarize (Otsu)
    cv::Mat preprocessed_BW1;
    cv::threshold(preprocessed_BW, preprocessed_BW1, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);

    // bwareaopen - remove connected components smaller than 5 pixels
    cv::Mat preprocessed_BW2 = preprocessed_BW1.clone();
    std::vector<std::vector<cv::Point>> preprocessed_contours;
    cv::Mat labels, stats, centroids;
    int preprocessed_n = cv::connectedComponentsWithStats(preprocessed_BW1, labels, stats, centroids);
    for (int i = 1; i < preprocessed_n; i++)
    {
        if (stats.at<int>(i, cv::CC_STAT_AREA) < 5)
        {
            cv::Mat mask = (labels == i);
            preprocessed_BW2.setTo(0, mask);
        }
    }

    // imcomplement
    cv::Mat preprocessed_BW3;
    cv::bitwise_not(preprocessed_BW2, preprocessed_BW3);

    cv::Mat roi_img = inputImg.clone();
    int correct_roi_idx = -1;
    for (size_t i = 0; i < detectedRois.size(); i++)
    {
        cv::rectangle(roi_img, detectedRois[i], cv::Scalar(0, 255, 0), 4);
        cv::Rect details_roi = detectedRois[i];

        save_img(outputImgPath, "preprocessed_BW3", preprocessed_BW3);

        cv::Mat roiMat = preprocessed_BW3(details_roi);
        OCRResult roiOcrResult = {};

        roiOcrResult = ocrWrapper.performOCR(roiMat.clone());
        if (roiOcrResult.confidence < 0.5)
        {
            platform_log("Low OCR confidence (%.2f) for ROI %d, skipping\n", roiOcrResult.confidence, i);
            continue;
        }

        // Strip all non-alphanumeric characters
        std::string cleanText;
        for (char c : roiOcrResult.text) {
            if (std::isalnum(static_cast<unsigned char>(c))) cleanText += c;
        }
        if (cleanText == "Details")
        {
            correct_roi_idx = i;
            result.detailsRoiIndex = i;
            platform_log("Found 'Details' with confidence %.2f in ROI %d\n", roiOcrResult.confidence, i);
        }
    }

    result.isDetected = 1;
    result.rois = detectedRois;
    save_img(outputImgPath, "BW3", BW3);

    if (correct_roi_idx == -1)
    {
        platform_log("Failed to find 'Details' in any ROI, defaulting to first detected ROI\n");
        result.detailsRoiIndex = -1;
        return result;
    }

    // Create offsets for score OCR
    cv::Rect ROI_Details = offsetToRoi(cv::Point(2054, 2348), cv::Point(2418, 2450));

    cv::Rect ROI_Score = offsetToRoi(cv::Point(2700, 2551), cv::Point(2968, 2611));
    cv::Rect ROI_Marvelous = offsetToRoi(cv::Point(1896, 2549), cv::Point(2018, 2599));
    cv::Rect ROI_Perfect = offsetToRoi(cv::Point(1896, 2608), cv::Point(2018, 2657));
    cv::Rect ROI_Great = offsetToRoi(cv::Point(1896, 2664), cv::Point(2018, 2702));
    cv::Rect ROI_Good = offsetToRoi(cv::Point(1896, 2727), cv::Point(2018, 2771));
    cv::Rect ROI_Miss = offsetToRoi(cv::Point(1896, 2825), cv::Point(2018, 2879));
    cv::Rect ROI_Flare = offsetToRoi(cv::Point(1649, 2466), cv::Point(1817, 2508));
    cv::Rect ROI_Title = offsetToRoi(cv::Point(1210, 2075), cv::Point(1744, 2133));
    cv::Rect ROI_Username = offsetToRoi(cv::Point(2180, 1388), cv::Point(2465, 1439));
    cv::Rect ROI_Difficulty = offsetToRoi(cv::Point(2056, 1463), cv::Point(2627, 1536));
    cv::Rect ROI_MaxCombo = offsetToRoi(cv::Point(2665, 2779), cv::Point(2797, 2831));

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
    double epsilon = 0.1 * cv::arcLength(hull, true);
    cv::approxPolyDP(hull, approx, epsilon, true);

    cv::Mat approx_img = inputImg.clone();
    for (size_t i = 0; i < approx.size(); i++)
    {
        cv::line(approx_img, approx[i], approx[(i + 1) % approx.size()],
                 cv::Scalar(0, 255, 0), 4);
        cv::circle(approx_img, approx[i], 12, cv::Scalar(0, 255, 255), -1);
    }

    save_img(outputImgPath, "extrema", approx_img);

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

    save_img(outputImgPath, "warped", warpedImg);

    // Read from offsets
    std::vector<cv::Point2f> tl_vec = {tl};
    std::vector<cv::Point2f> tl_transformed;
    cv::perspectiveTransform(tl_vec, tl_transformed, H);

    cv::Point2f warped_details_top_left = tl_transformed[0];

    OCRResults ocrResults = {};

    ocrResults.score = getPreprocessedRoiImage(
        warpedImg,
        ROI_Score,
        ROI_Details,
        warped_details_top_left,
        cv::Point(5, 5),
        "score",
        outputImgPath);

    ocrResults.marvelous = getPreprocessedRoiImage(
        warpedImg,
        ROI_Marvelous,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 0),
        "marvelous",
        outputImgPath);

    ocrResults.perfect = getPreprocessedRoiImage(
        warpedImg,
        ROI_Perfect,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 4),
        "perfect",
        outputImgPath);

    ocrResults.great = getPreprocessedRoiImage(
        warpedImg,
        ROI_Great,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 5),
        "great",
        outputImgPath);

    ocrResults.good = getPreprocessedRoiImage(
        warpedImg,
        ROI_Good,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 5),
        "good",
        outputImgPath);

    ocrResults.miss = getPreprocessedRoiImage(
        warpedImg,
        ROI_Miss,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 0),
        "miss",
        outputImgPath);

    ocrResults.flare = getPreprocessedRoiImage(
        warpedImg,
        ROI_Flare,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 5),
        "flare",
        outputImgPath);

    ocrResults.title = getPreprocessedRoiImage(
        warpedImg,
        ROI_Title,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 0),
        "title",
        outputImgPath);

    ocrResults.username = getPreprocessedRoiImage(
        warpedImg,
        ROI_Username,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 0),
        "username",
        outputImgPath);

    ocrResults.difficulty = getPreprocessedRoiImage(
        warpedImg,
        ROI_Difficulty,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 0),
        "difficulty",
        outputImgPath);

    ocrResults.max_combo = getPreprocessedRoiImage(
        warpedImg,
        ROI_MaxCombo,
        ROI_Details,
        warped_details_top_left,
        cv::Point(0, 0),
        "max_combo",
        outputImgPath);

    result.ocrResults = ocrResults;
    return result;
}

OCRResult DdrocrInstance::getPreprocessedRoiImage(
    const cv::Mat &warpedImg,
    const cv::Rect &ROI_Target,
    const cv::Rect &ROI_Details,
    const cv::Point &warped_details_top_left,
    const cv::Point &expand,
    const std::string &imageName,
    const std::string &outputImgPath)
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

    cv::Mat cropped;
    try
    {
        cropped = warpedImg(roi_warped);
    }
    catch (...)
    {
        return result;
    }

    if (cropped.empty())
        return result;

    // Preprocessing: top-hat + grayscale + threshold
    cv::Mat kernel_tophat = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(31, 31));

    cv::Mat corrected;
    cv::morphologyEx(cropped, corrected, cv::MORPH_TOPHAT, kernel_tophat);

    cv::Mat gray;
    cv::cvtColor(corrected, gray, cv::COLOR_BGR2GRAY);

    cv::Mat BW1;
    cv::threshold(gray, BW1, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);

    cv::Mat BW2;
    cv::bitwise_not(BW1, BW2);

    save_img(outputImgPath, imageName, BW2);

    result = ocrWrapper.performOCR(BW2.clone());

    // TODO: This is kinda garbage, we should prioritize fixing the underlying cause of bad detection 
    // OR not have this platform specific hack here

    // Fallback to classify 0/1 explicitly
    if (result.confidence == 0)
    {
        char digit = classifyDigit_0_or_1(BW2);
        result.text = digit;
    }

    platform_log("[OCR] [%s] ROI(%d,%d %dx%d) confidence=%.2f text=%s\n",
                 imageName.c_str(),
                 roi_warped.x, roi_warped.y,
                 roi_warped.width, roi_warped.height,
                 result.confidence,
                 result.text.c_str());

    return result;
}


// Returns either '0', '1', or '?' if unknown
char DdrocrInstance::classifyDigit_0_or_1(const cv::Mat &input)
{
    // 1. Convert to grayscale if needed
    cv::Mat gray;
    if (input.channels() == 3)
        cv::cvtColor(input, gray, cv::COLOR_BGR2GRAY);
    else
        gray = input.clone();

    // 2. Binarize (digit should be black)
    cv::Mat binary;
    cv::threshold(gray, binary, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
    // Now digit = white, background = black

    // 3. Find contours with hierarchy (needed to detect holes)
    std::vector<std::vector<cv::Point>> contours;
    std::vector<cv::Vec4i> hierarchy;

    cv::findContours(binary, contours, hierarchy,
                     cv::RETR_CCOMP, cv::CHAIN_APPROX_SIMPLE);

    if (contours.empty())
        return '?';

    // 4. Count how many contours are "holes" (child contours)
    int holeCount = 0;
    for (size_t i = 0; i < hierarchy.size(); i++)
    {
        int parentIdx = hierarchy[i][3]; // parent contour index
        if (parentIdx != -1)
            holeCount++;
    }

    platform_log("hole: %d\n", holeCount);

    // 5. Decide digit based on hole count
    if (holeCount == 1)
        return '0';
    if (holeCount == 0)
        return '1';

    return '?'; // unexpected case
}

void DdrocrInstance::save_img(const std::string &outputImgPath, const std::string &fileName, cv::Mat img)
{
    char path[250];
    snprintf(path, sizeof(path), "%s/%s.jpg", outputImgPath.c_str(), fileName.c_str());
    platform_log("wrote: %s\n", path);
    int imwrite_result = cv::imwrite(path, img);
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
