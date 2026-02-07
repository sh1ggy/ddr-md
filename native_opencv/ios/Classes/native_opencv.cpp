#include <opencv2/opencv.hpp>
#include <chrono>

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

void save_img(const string &outputImgPath, const string &fileName, Mat img)
{
    char path[250];
    snprintf(path, sizeof(path), "%s/%s.jpg", outputImgPath.c_str(), fileName.c_str());
    platform_log("wrote: %s\n", path);
    int imwrite_result = imwrite(path, img);
}

typedef struct ProcessImgResult
{
    Mat img;
    int32_t isDetected;
    vector<Rect> rois;
};

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

    // For debug
    Mat roi_img = inputImg.clone();
    for (size_t i = 0; i < detectedRois.size(); i++)
    {
        rectangle(roi_img, detectedRois[i], Scalar(0, 255, 0), 4);
    }

    result.isDetected = 1;
    platform_log("%d", largestRoiAreaIndex);
    // copy all detected rois so callers can access them
    result.rois = detectedRois;
    save_img(outputImgPath, "BW3", BW3); // save bW3

    // Create offsets for score OCR
    Point2d top_left_details(2054, 2345);
    Point2d bot_right_details(2417, 2454);
    Point2d top_left_score(2700, 2551);
    Point2d bot_right_score(2953, 2611);
    Point2d top_left_difficulty(1657, 2471);

    Size score_box_size(bot_right_score.x - top_left_score.x, bot_right_score.y - top_left_score.y);
    Point2d score_offset(top_left_score.x - top_left_details.x, top_left_score.y - top_left_details.y);

    Point2d difficulty_offset(top_left_difficulty.x - top_left_details.x, top_left_difficulty.y - top_left_details.y);
    Size difficulty_box_size(score_box_size.width * 0.8, score_box_size.height);

    int correct_roi_idx = 5; // HARDCODED

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

    vector<Point2f> ordered = {tl, tr, br, bl};

    // Perform homography
    Point2f ref_tl(top_left_details.x, top_left_details.y);
    Point2f ref_tr(bot_right_details.x, top_left_details.y);
    Point2f ref_br(bot_right_details.x, bot_right_details.y);
    Point2f ref_bl(top_left_details.x, bot_right_details.y);

    vector<Point2f> referencePoints = {ref_tl, ref_tr, ref_br, ref_bl};

    Mat H = getPerspectiveTransform(ordered, referencePoints);

    Mat warpedImg;
    // The size doesnt affect the output to ROI (as long as the size is big enough)
    Size beeg = Size(4000, 5000);
    warpPerspective(inputImg, warpedImg, H, beeg);

    save_img(outputImgPath, "warped", warpedImg);

    // Read from offsets
    vector<Point2f> tl_vec = {tl};
    vector<Point2f> tl_transformed;
    perspectiveTransform(tl_vec, tl_transformed, H);

    Point2f warped_details_top_left = tl_transformed[0];
    int numAdditionalPixels = 5;
    Rect score_roi_warped(warped_details_top_left.x + score_offset.x - numAdditionalPixels,
                          warped_details_top_left.y + score_offset.y - numAdditionalPixels,
                          score_box_size.width + 2 * numAdditionalPixels,
                          score_box_size.height + 2 * numAdditionalPixels);

    // Ensure ROI is within image bounds
    score_roi_warped &= Rect(0, 0, warpedImg.cols, warpedImg.rows);

    Mat img_cropped = warpedImg(score_roi_warped);

    save_img(outputImgPath, "cropped", img_cropped);

    Mat kernel_tophat = getStructuringElement(MORPH_ELLIPSE, Size(31, 31));
    Mat Icorrected_score;
    morphologyEx(img_cropped, Icorrected_score, MORPH_TOPHAT, kernel_tophat);

    Mat BW1_score;
    cvtColor(Icorrected_score, BW1_score, COLOR_BGR2GRAY);
    threshold(BW1_score, BW1_score, 0, 255, THRESH_BINARY + THRESH_OTSU);

    save_img(outputImgPath, "tophat_op", Icorrected_score);
    save_img(outputImgPath, "Score_bin", BW1_score);
    
    Mat BW2_score;
    bitwise_not(BW1_score, BW2_score);
    save_img(outputImgPath, "Score_bin2", BW2_score);
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
        int32_t *outputRoisCount)
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
