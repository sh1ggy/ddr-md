#ifdef NO
#define APPLE_NO_DEFINED
#undef NO
#endif

#include <opencv2/opencv.hpp>
#include <chrono>
#include "ocr_wrapper.h"

#ifdef APPLE_NO_DEFINED
#define NO (BOOL)0
#endif

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32)
#define IS_WIN32
#endif

#ifdef __ANDROID__
#include <android/log.h>
#endif

#ifdef IS_WIN32
#include <windows.h>
#endif

#if defined(__GNUC__)
// Attributes to prevent 'unused' function from being removed and to make it visible
#define FUNCTION_ATTRIBUTE __attribute__((visibility("default"))) __attribute__((used))
#elif defined(_MSC_VER)
// Marking a function for export
#define FUNCTION_ATTRIBUTE __declspec(dllexport)
#endif

// #include <leptonica/allheaders.h>
// #include <tesseract/baseapi.h>

typedef void *tess_api_ptr_t;
typedef void *pix_image_ptr_t;

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

using namespace cv;
using namespace std;

const int max_value_H = 360 / 2;
const int max_value = 255;

long long int get_now()
{
    return chrono::duration_cast<std::chrono::milliseconds>(
                                                            chrono::system_clock::now().time_since_epoch())
    .count();
}

void platform_log(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
#ifdef __ANDROID__
    __android_log_vprint(ANDROID_LOG_VERBOSE, "ndk", fmt, args);
#elif defined(IS_WIN32)
    char *buf = new char[4096];
    std::fill_n(buf, 4096, '\0');
    _vsprintf_p(buf, 4096, fmt, args);
    OutputDebugStringA(buf);
    delete[] buf;
#else
    vprintf(fmt, args);
#endif
    va_end(args);
}

// Returns either '0', '1', or '?' if unknown
char classifyDigit_0_or_1(const cv::Mat &input)
{
    // 1. Convert to grayscale if needed
    Mat gray;
    if (input.channels() == 3)
        cvtColor(input, gray, COLOR_BGR2GRAY);
    else
        gray = input.clone();
    
    // 2. Binarize (digit should be black)
    Mat binary;
    threshold(gray, binary, 0, 255, THRESH_BINARY_INV | THRESH_OTSU);
    // Now digit = white, background = black
    
    // 3. Find contours with hierarchy (needed to detect holes)
    std::vector<std::vector<Point>> contours;
    std::vector<Vec4i> hierarchy;
    
    findContours(binary, contours, hierarchy,
                 RETR_CCOMP, CHAIN_APPROX_SIMPLE);
    
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

static char* allocCString(const std::string& s) {
    size_t len = s.length();
    char* buf = (char*)malloc(len + 1);
    memcpy(buf, s.c_str(), len + 1);
    return buf;
}

void save_img(const string &outputImgPath, const string &fileName, Mat img)
{
    char path[250];
    snprintf(path, sizeof(path), "%s/%s.jpg", outputImgPath.c_str(), fileName.c_str());
    platform_log("wrote: %s\n", path);
    int imwrite_result = imwrite(path, img);
}

Rect expandRoi(Rect roi, Point expand)
{
    return Rect(
                roi.x - expand.x,
                roi.y - expand.y,
                roi.width + expand.x * 2,
                roi.height + expand.y * 2);
}

vector<Point2f> rectToPoints(const Rect &r)
{
    Point2f tl(r.x, r.y);
    Point2f tr(r.x + r.width, r.y);
    Point2f br(r.x + r.width, r.y + r.height);
    Point2f bl(r.x, r.y + r.height);
    
    return {tl, tr, br, bl};
}

Rect offsetToRoi(Point tl, Point br, Point expansion = {0, 0})
{
    // Width/height from raw coordinates
    int width = br.x - tl.x;
    int height = br.y - tl.y;
    
    // Expand ROI by expansion.x and expansion.y on all sides
    int x = tl.x - expansion.x;
    int y = tl.y - expansion.y;
    width += expansion.x * 2;
    height += expansion.y * 2;
    
    return Rect(x, y, width, height);
}

OCRResult getPreprocessedRoiImage(
                                  const Mat &warpedImg,
                                  const Rect &ROI_Target,
                                  const Rect &ROI_Details,
                                  const Point &warped_details_top_left,
                                  const Point &expand,
                                  const string &imageName,
                                  const string &outputImgPath)
{
    OCRResult result{}; // Always have a valid return object
    
    if (warpedImg.empty())
        return result;
    
    // Offset for ROI
    Point2d offset(
                   ROI_Target.x - ROI_Details.x,
                   ROI_Target.y - ROI_Details.y);
    
    Rect roi_warped(
                    warped_details_top_left.x + offset.x,
                    warped_details_top_left.y + offset.y,
                    ROI_Target.width,
                    ROI_Target.height);
    
    roi_warped = expandRoi(roi_warped, expand);
    
    Rect imgBounds(0, 0, warpedImg.cols, warpedImg.rows);
    roi_warped &= imgBounds;
    
    if (roi_warped.width <= 0 || roi_warped.height <= 0)
        return result;
    
    Mat cropped;
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
    Mat kernel_tophat = getStructuringElement(MORPH_ELLIPSE, Size(31, 31));
    
    Mat corrected;
    morphologyEx(cropped, corrected, MORPH_TOPHAT, kernel_tophat);
    
    Mat gray;
    cvtColor(corrected, gray, COLOR_BGR2GRAY);
    
    Mat BW1;
    threshold(gray, BW1, 0, 255, THRESH_BINARY | THRESH_OTSU);
    
    Mat BW2;
    bitwise_not(BW1, BW2);
    
    save_img(outputImgPath, imageName, BW2);
    
    // OCR call
#ifdef __ANDROID__
    // TODO: tesseract
    result = {};
#elif __APPLE__
    result = OCRWrapper::performOCR(
                                    BW2.data,
                                    BW2.cols,
                                    BW2.rows,
                                    BW2.step,
                                    BW2.channels());
#else
    // invalid platform.
    result = {};
#endif
    
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

typedef struct 
{
    Mat img;
    int32_t isDetected;
    vector<Rect> rois;
    int32_t detailsRoiIndex;
    OCRResults ocrResults;
} ProcessImgResult;

typedef struct
{
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
} COCRStrings;

ProcessImgResult process_image(Mat inputImg, const string &outputImgPath)
{
    ProcessImgResult result;
    
    Mat grayImg;
    cvtColor(inputImg, grayImg, COLOR_BGR2GRAY);
    
    // Selecting Details box - HSV mask
    Mat imgHSV;
    cvtColor(inputImg, imgHSV, COLOR_BGR2HSV);
    
    double channel1Min = 0.380;
    double channel1Max = 0.531;
    double channel2Min = 0.204;
    double channel2Max = 1.000;
    double channel3Min = 0.592;
    double channel3Max = 1.000;
    
    // Use inRange for HSV thresholding
    Scalar lowerHSV(channel1Min * max_value_H, channel2Min * max_value, channel3Min * max_value);
    Scalar upperHSV(channel1Max * max_value_H, channel2Max * max_value, channel3Max * max_value);
    
    Mat BW_HSV;
    inRange(imgHSV, lowerHSV, upperHSV, BW_HSV);
    
    // Do blob detection and filter small blobs
    vector<vector<Point>> contours;
    findContours(BW_HSV, contours, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);
    
    Mat BW2 = Mat::zeros(BW_HSV.size(), CV_8U);
    for (size_t i = 0; i < contours.size(); i++)
    {
        double area = contourArea(contours[i]);
        if (area >= 3000 && area <= 50000)
        {
            drawContours(BW2, contours, i, Scalar(255), FILLED);
        }
    }
    
    int m = 360;
    int n = 90;
    
    // Create opening kernel using byte array (faster than getStructuringElement)
    int open_width = m * 0.1;
    int open_height = n * 0.1;
    uchar *open_data = new uchar[open_height * open_width];
    memset(open_data, 255, open_height * open_width);
    Mat SE_open(open_height, open_width, CV_8U, open_data);
    
    // TODO: refactor stateful object to avoid recreating structuring elements every time cache optimisation
    auto start_open = chrono::high_resolution_clock::now();
    Mat BW3;
    morphologyEx(BW2, BW3, MORPH_OPEN, SE_open);
    save_img(outputImgPath, "BW_HSV", BW_HSV);
    save_img(outputImgPath, "BW2", BW2);
    save_img(outputImgPath, "BW3", BW3);
    auto end_open = chrono::high_resolution_clock::now();
    auto duration_open = chrono::duration_cast<chrono::microseconds>(end_open - start_open);
    cout << "Opening operation with byte array kernel: " << duration_open.count() << " microseconds" << endl;
    
    // Dont need close for now, works fiune with JUST open to get rid of noise
    
    //// Create closing kernel using byte array
    // int close_width = m * 1.2;
    // int close_height = n * 1.2;
    // uchar* close_data = new uchar[close_height * close_width];
    // memset(close_data, 255, close_height * close_width);
    // Mat SE_close(close_height, close_width, CV_8U, close_data);
    
    // auto start_close = chrono::high_resolution_clock::now();
    // Mat BW4;
    // morphologyEx(BW3, BW4, MORPH_CLOSE, SE_close);
    // auto end_close = chrono::high_resolution_clock::now();
    // auto duration_close = chrono::duration_cast<chrono::microseconds>(end_close - start_close);
    // cout << "Closing operation with byte array kernel: " << duration_close.count() << " microseconds" << endl;
    
    delete[] open_data;
    // delete[] close_data;
    
    // Get bounding boxes
    vector<vector<Point>> contours_final;
    findContours(BW3.clone(), contours_final, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);
    
    vector<Rect> detectedRois;
    
    int largestRoiAreaIndex = 0;
    double largestRoiArea = 0;
    
    // Looping through contours to find its area & bounding box
    for (size_t i = 0; i < contours_final.size(); i++)
    {
        
        double thisRoi = contourArea(contours_final[i]);
        detectedRois.push_back(boundingRect(contours_final[i]));
        
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
    
    // Preprocess image fro OCR on details
    /*
     Icorrected = imbothat(img,strel("disk",15));
     
     % gaus filter to reduce LED screen noise
     Ifiltered = imgaussfilt(Icorrected, 1);
     
     BW = rgb2gray(Ifiltered);
     BW1 = imbinarize(BW);
     
     % morphological filtering (no reconstruction as some letters are non
     % contiguous)
     BW2 = bwareaopen(BW1, 5);
     
     % Black text on white background preferred for OCR
     BW3 = imcomplement(BW2);
     */
    
    // imbothat = closing - original (bottom hat)
    Mat kernel = getStructuringElement(MORPH_ELLIPSE, Size(31, 31)); // radius 15 -> size 31
    Mat closed, Icorrected;
    morphologyEx(inputImg, closed, MORPH_CLOSE, kernel);
    subtract(closed, inputImg, Icorrected);
    
    // gaussian filter sigma=1
    Mat Ifiltered;
    GaussianBlur(Icorrected, Ifiltered, Size(0, 0), 1.0);
    
    // rgb2gray
    Mat preprocessed_BW;
    cvtColor(Ifiltered, preprocessed_BW, COLOR_BGR2GRAY);
    
    // imbinarize (Otsu)
    Mat preprocessed_BW1;
    threshold(preprocessed_BW, preprocessed_BW1, 0, 255, THRESH_BINARY | THRESH_OTSU);
    
    // bwareaopen - remove connected components smaller than 5 pixels
    Mat preprocessed_BW2 = preprocessed_BW1.clone();
    std::vector<std::vector<Point>> preprocessed_contours;
    Mat labels, stats, centroids;
    int preprocessed_n = connectedComponentsWithStats(preprocessed_BW1, labels, stats, centroids);
    for (int i = 1; i < n; i++)
    {
        if (stats.at<int>(i, CC_STAT_AREA) < 5)
        {
            Mat mask = (labels == i);
            preprocessed_BW2.setTo(0, mask);
        }
    }
    
    // imcomplement
    Mat preprocessed_BW3;
    bitwise_not(preprocessed_BW2, preprocessed_BW3);
    
    Mat roi_img = inputImg.clone(); // TODO rename to all_rois_img
    int correct_roi_idx = -1;
    for (size_t i = 0; i < detectedRois.size(); i++)
    {
        rectangle(roi_img, detectedRois[i], Scalar(0, 255, 0), 4);
        Rect details_roi = detectedRois[i];
        // Mat details_roi_img = inputImg(details_roi);
        //  TODO: NOT PERFORMANT pass in just ROI or pass in input image once at start of fun
        save_img(outputImgPath, "preprocessed_BW3", preprocessed_BW3); // save bW3
        
        cv::Mat roiMat = preprocessed_BW3(details_roi);
        OCRResult roiOcrResult = {};
#ifdef __ANDROID__
        // TODO: tesseract
        roiOcrResult = {};
#elif __APPLE__
        roiOcrResult = OCRWrapper::performOCR(
                                           roiMat.data,
                                           roiMat.cols,
                                           roiMat.rows,
                                           roiMat.step,
                                           roiMat.channels());
#else
        roiOcrResult = {};
#endif
        if (roiOcrResult.confidence < 0.5) // confidence threshold, can be tuned
        {
            platform_log("Low OCR confidence (%.2f) for ROI %d, skipping\n", roiOcrResult.confidence, i);
            continue;
        }
        if (roiOcrResult.text == "Details")
        {
            correct_roi_idx = i;
            result.detailsRoiIndex = i;
            platform_log("Found 'Details' with confidence %.2f in ROI %d\n", roiOcrResult.confidence, i);
        }
    }
    
    result.isDetected = 1;
    // copy all detected rois so callers can access them
    result.rois = detectedRois;
    save_img(outputImgPath, "BW3", BW3); // save bW3
    
    if (correct_roi_idx == -1)
    {
        platform_log("Failed to find 'Details' in any ROI, defaulting to first detected ROI\n");
        result.detailsRoiIndex = -1;
        return result;
    }
    
    // Create offsets for score OCR
    Rect ROI_Details = offsetToRoi(Point(2054, 2348), Point(2418, 2450));
    
    Rect ROI_Score = offsetToRoi(Point(2700, 2551), Point(2968, 2611));
    Rect ROI_Marvelous = offsetToRoi(Point(1896, 2549), Point(2018, 2599));
    Rect ROI_Perfect = offsetToRoi(Point(1896, 2608), Point(2018, 2657));
    Rect ROI_Great = offsetToRoi(Point(1896, 2664), Point(2018, 2702));
    Rect ROI_Good = offsetToRoi(Point(1896, 2727), Point(2018, 2771));
    Rect ROI_Miss = offsetToRoi(Point(1896, 2825), Point(2018, 2879));
    Rect ROI_Flare = offsetToRoi(Point(1649, 2466), Point(1817, 2508));
    Rect ROI_Title = offsetToRoi(Point(1210, 2075), Point(1744, 2133));
    Rect ROI_Username = offsetToRoi(Point(2180, 1388), Point(2465, 1439));
    Rect ROI_Difficulty = offsetToRoi(Point(2056, 1463), Point(2627, 1536));
    Rect ROI_MaxCombo = offsetToRoi(Point(2665, 2779), Point(2797, 2831));
    
    if (result.rois.size() <= correct_roi_idx)
    {
        platform_log("Not enough ROIs detected, defaulting to first detected ROI\n");
        result.isDetected = 1;
        return result;
    }
    
    // Using regionprops Convex hull method
    vector<Point> hull;
    convexHull(contours_final[correct_roi_idx], hull);
    
    // Approximate polygon
    vector<Point> approx;
    // Use the perimeter (arcLength) as part of the calculation for how much the polygon should be reduced.
    double epsilon = 0.1 * arcLength(hull, true);
    approxPolyDP(hull, approx, epsilon, true);
    
    Mat approx_img = inputImg.clone();
    for (size_t i = 0; i < approx.size(); i++)
    {
        line(approx_img, approx[i], approx[(i + 1) % approx.size()],
             Scalar(0, 255, 0), 4);
        circle(approx_img, approx[i], 12, Scalar(0, 255, 255), -1);
    }
    
    save_img(outputImgPath, "extrema", approx_img);
    
    // Get first 4 points and order them
    vector<Point2f> pts;
    for (int i = 0; i < min(4, (int)approx.size()); i++)
    {
        pts.push_back(Point2f(approx[i].x, approx[i].y));
    }
    
    // Order points: top-left, top-right, bottom-right, bottom-left
    vector<pair<float, int>> sums;
    for (int i = 0; i < pts.size(); i++)
    {
        sums.push_back(make_pair(pts[i].x + pts[i].y, i));
    }
    sort(sums.begin(), sums.end());
    
    Point2f tl = pts[sums[0].second];
    Point2f br = pts[sums[3].second];
    
    Point2f remaining[2] = {pts[sums[1].second], pts[sums[2].second]};
    Point2f tr = remaining[0].x > remaining[1].x ? remaining[0] : remaining[1];
    Point2f bl = remaining[0].x < remaining[1].x ? remaining[0] : remaining[1];
    
    vector<Point2f> detailsPoints = {tl, tr, br, bl};
    // Perform homography
    vector<Point2f> detailsReferencePoints = rectToPoints(ROI_Details);
    Mat H = getPerspectiveTransform(detailsPoints, detailsReferencePoints);
    
    Mat warpedImg;
    // The size doesnt affect the output to ROI (as long as the size is big enough)
    Size beeg = Size(4000, 5000);
    // Size beeg = Size(1000, 1000);
    warpPerspective(inputImg, warpedImg, H, beeg);
    
    save_img(outputImgPath, "warped", warpedImg);
    
    // Read from offsets
    vector<Point2f> tl_vec = {tl};
    vector<Point2f> tl_transformed;
    perspectiveTransform(tl_vec, tl_transformed, H);
    
    Point2f warped_details_top_left = tl_transformed[0];
    int numAdditionalPixels = 5;
    
    OCRResults ocrResults = {};
    
    ocrResults.score = getPreprocessedRoiImage(
                                               warpedImg,
                                               ROI_Score,
                                               ROI_Details,
                                               warped_details_top_left,
                                               Point(5, 5),
                                               "score",
                                               outputImgPath);
    // #endregion
    
    ocrResults.marvelous = getPreprocessedRoiImage(
                                                   warpedImg,
                                                   ROI_Marvelous,
                                                   ROI_Details,
                                                   warped_details_top_left,
                                                   Point(0, 0),
                                                   "marvelous",
                                                   outputImgPath);
    
    ocrResults.perfect = getPreprocessedRoiImage(
                                                 warpedImg,
                                                 ROI_Perfect,
                                                 ROI_Details,
                                                 warped_details_top_left,
                                                 Point(0, 4),
                                                 "perfect",
                                                 outputImgPath);
    
    ocrResults.great = getPreprocessedRoiImage(
                                               warpedImg,
                                               ROI_Great,
                                               ROI_Details,
                                               warped_details_top_left,
                                               Point(0, 5),
                                               "great",
                                               outputImgPath);
    
    ocrResults.good = getPreprocessedRoiImage(
                                              warpedImg,
                                              ROI_Good,
                                              ROI_Details,
                                              warped_details_top_left,
                                              Point(0, 5),
                                              "good",
                                              outputImgPath);
    
    ocrResults.miss = getPreprocessedRoiImage(
                                              warpedImg,
                                              ROI_Miss,
                                              ROI_Details,
                                              warped_details_top_left,
                                              Point(0, 0),
                                              "miss",
                                              outputImgPath);
    
    ocrResults.flare = getPreprocessedRoiImage(
                                               warpedImg,
                                               ROI_Flare,
                                               ROI_Details,
                                               warped_details_top_left,
                                               Point(0, 5),
                                               "flare",
                                               outputImgPath);
    
    ocrResults.title = getPreprocessedRoiImage(
                                               warpedImg,
                                               ROI_Title,
                                               ROI_Details,
                                               warped_details_top_left,
                                               Point(0, 0),
                                               "title",
                                               outputImgPath);
    
    ocrResults.username = getPreprocessedRoiImage(
                                                  warpedImg,
                                                  ROI_Username,
                                                  ROI_Details,
                                                  warped_details_top_left,
                                                  Point(0, 0),
                                                  "username",
                                                  outputImgPath);
    
    ocrResults.difficulty = getPreprocessedRoiImage(
                                                    warpedImg,
                                                    ROI_Difficulty,
                                                    ROI_Details,
                                                    warped_details_top_left,
                                                    Point(0, 0),
                                                    "difficulty",
                                                    outputImgPath);
    
    ocrResults.max_combo = getPreprocessedRoiImage(
                                                   warpedImg,
                                                   ROI_MaxCombo,
                                                   ROI_Details,
                                                   warped_details_top_left,
                                                   Point(0, 0),
                                                   "max_combo",
                                                   outputImgPath);
    
    result.ocrResults = ocrResults;
    return result;
}

// Avoiding name mangling
extern "C"
{
FUNCTION_ATTRIBUTE
const char *version()
{
    return CV_VERSION;
}

FUNCTION_ATTRIBUTE
void process_picked_image(
                          char *inputImagePath,
                          int32_t *outputIsDetected,
                          char *outputImgPath,
                          int32_t **outputRois,
                          int32_t *outputRoisCount,
                          int32_t *outputdetailsRoiIndex,
                          COCRStrings *outStrings)
{
    long long start = get_now();
    Mat img = imread(inputImagePath);
    if (img.empty())
    {
        platform_log("Could not open or find the image: %s\n", inputImagePath);
        return;
    }
    string staticOutputImgPath = string(outputImgPath);
    ProcessImgResult result = process_image(img, staticOutputImgPath);
    if (!result.isDetected)
    {
        platform_log("No OCR region detected, skipping saving processed image.\n");
        *outputIsDetected = result.isDetected;
        return;
    }
    platform_log("result isDetected: %d\n", result.isDetected);
    int actualCount = (int)result.rois.size();
    
    platform_log("%d", actualCount);
    int evalInMillis = static_cast<int>(get_now() - start);
    
    // copy all detected rois to outputRects
    *outputRois = (int32_t *)malloc(sizeof(int32_t) * actualCount * 4);
    int32_t *roisPtr = *outputRois;
    platform_log("C++ POINTER ADDR: %d \n", roisPtr);
    
    for (size_t i = 0; i < result.rois.size(); i++)
    {
        roisPtr[i * 4 + 0] = result.rois[i].tl().x;
        roisPtr[i * 4 + 1] = result.rois[i].tl().y;
        roisPtr[i * 4 + 2] = result.rois[i].width;
        roisPtr[i * 4 + 3] = result.rois[i].height;
        platform_log("Detected OCR ROI: x=%d, y=%d, w=%d, h=%d\n", outputRois[i * 4 + 0], outputRois[i * 4 + 1], outputRois[i * 4 + 2], outputRois[i * 4 + 3]);
    }
    *outputRoisCount = actualCount;
    *outputIsDetected = result.isDetected;
    *outputdetailsRoiIndex = result.detailsRoiIndex;
    
    const auto &ocr = result.ocrResults;
    outStrings->score      = allocCString(ocr.score.text);
    outStrings->marvelous  = allocCString(ocr.marvelous.text);
    outStrings->perfect    = allocCString(ocr.perfect.text);
    outStrings->great      = allocCString(ocr.great.text);
    outStrings->good       = allocCString(ocr.good.text);
    outStrings->miss       = allocCString(ocr.miss.text);
    outStrings->flare      = allocCString(ocr.flare.text);
    outStrings->title      = allocCString(ocr.title.text);
    outStrings->username   = allocCString(ocr.username.text);
    outStrings->difficulty = allocCString(ocr.difficulty.text);
    outStrings->maxCombo   = allocCString(ocr.max_combo.text);
}

// TODO pass in img rotation
FUNCTION_ATTRIBUTE
void process_camera_image(
                          int32_t imgWidth,
                          int32_t imgHeight,
                          int32_t bytesPerPixel,
                          uint8_t *imgBuffer,
                          int32_t *outputRoi,
                          int32_t *outputIsDetected,
                          int32_t *outputImgSize,
                          uint8_t *outputImgBuff,
                          char *outputImgPath)
{
    long long start = get_now();
    Mat img;
    
#ifdef __ANDROID__
    
    // yuv is weird, see https://www.youtube.com/watch?v=q_mhF_Ys6nw
    Mat frame(imgHeight + imgHeight / 2, imgWidth, CV_8UC1, imgBuffer); // frame size: 1600x1800, frame channels: 1 , type = 0
    // cvtColor(frame, img, COLOR_YUV2RGB);
    cvtColor(frame, img, COLOR_YUV2BGR_NV21);
    rotate(img, img, ROTATE_90_CLOCKWISE);
    // platform_log("Image size: %dx%d\n", img.cols, img.rows); // 1600x1200,  Image channels: 3, Image type: 16
    // platform_log("Image channels: %d\n", img.channels());
    // platform_log("Image depth: %d\n", img.depth());
    // platform_log("Image type: %d\n", img.type());
#else
    img = Mat(imgHeight, imgWidth, CV_8UC4, imgBuffer);
    platform_log("Image size: %dx%d\n", img.cols, img.rows);
    platform_log("Image channels: %d\n", img.channels());
    platform_log("Image depth: %d\n", img.depth());
    platform_log("Image type: %d\n", img.type());
#endif
    
    // tesseract::TessBaseAPI *api = new tesseract::TessBaseAPI();
    // api->Init(nullptr, "eng", tesseract::OEM_LSTM_ONLY);
    // api->SetPageSegMode(tesseract::PSM_SINGLE_LINE);
    
    // platform_log("Tesseract version: %s\n, datapath : %s\n", api->Version(), api->GetDatapath());
    
    //    api->SetVariable("tessedit_char_whitelist", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
    // api->SetImage(img.data, img.cols, img.rows, 3, img.step);
    
    // std::string outText = std::string(api->GetUTF8Text());
    
    // platform_log("OCR Output: %s\n", outText.c_str());
    
    // api->End();
    
    if (img.empty())
    {
        platform_log("Could not open or find the image: %s\n", outputImgPath);
    }
    
    // INIT
    // imwrite(outputImgPath, img);
    platform_log("Saved input image to %s\n", outputImgPath);
    try
    {
        ProcessImgResult result = process_image(img, outputImgPath);
        if (!result.isDetected)
        {
            platform_log("No OCR region detected, skipping saving processed image.\n");
            *outputIsDetected = result.isDetected;
            return;
        }
        // imwrite(outputImgPath, result.BW3);
        platform_log("Saved processed image to %s\n", outputImgPath);
        // printf("ocr roi size: x=%d, y=%d, w=%d, h=%d\n", ocr_roi[0].x, ocr_roi[0].y, ocr_roi[0].width, ocr_roi[0].height);
        *outputIsDetected = result.isDetected;
        outputRoi[0] = result.rois[0].tl().x;
        outputRoi[1] = result.rois[0].tl().y;
        outputRoi[2] = result.rois[0].width;
        outputRoi[3] = result.rois[0].height;
        
        platform_log("Returned OCR ROI: x=%d, y=%d, w=%d, h=%d\n", outputRoi[0], outputRoi[1], outputRoi[2], outputRoi[3]);
        return;
    }
    catch (cv::Exception &e)
    {
        platform_log(e.what());
        return;
    }
}

// This doesnt work but doesnt crash either,
// global cap.cpp:480 open VIDEOIO(ANDROID_NATIVE): backend is
//  generally available but can't be used to capture by index
FUNCTION_ATTRIBUTE
void camera_snapshot(char *outputImagePath)
{
    long long start = get_now();
    
    string buildInfo = cv::getBuildInformation();
    platform_log("OpenCV Build Information:\n%s\n", buildInfo.c_str());
    
    VideoCapture cap(0);
    
    cap.open(0, cv::CAP_ANDROID);
    
    if (!cap.isOpened())
    {
        platform_log("Cannot open camera\n");
        return;
    }
    
    Mat frame;
    cap >> frame;
    
    if (frame.empty())
    {
        platform_log("Cannot capture frame\n");
        return;
    }
    
    Mat gray;
    cvtColor(frame, gray, COLOR_BGR2GRAY);
    
    imwrite(outputImagePath, gray);
    
    int evalInMillis = static_cast<int>(get_now() - start);
    platform_log("Picture taken and processed!\n");
    platform_log("Size: %dx%d\n", frame.cols, frame.rows);
    platform_log("Camera snapshot done in %dms\n", evalInMillis);
}
}
