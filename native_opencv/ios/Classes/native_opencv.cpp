#ifdef NO
#define APPLE_NO_DEFINED
#undef NO
#endif

#include <opencv2/opencv.hpp>
#include <chrono>
#include "ocr_wrapper.h"
#include "ddrocr_instance.h"

#ifdef APPLE_NO_DEFINED
#define NO (BOOL)0
#endif

#ifdef __ANDROID__
#include <android/log.h>
#endif

#if defined(__GNUC__)
// Attributes to prevent 'unused' function from being removed and to make it visible
#define FUNCTION_ATTRIBUTE __attribute__((visibility("default"))) __attribute__((used))
#elif defined(_MSC_VER)
// Marking a function for export
#define FUNCTION_ATTRIBUTE __declspec(dllexport)
#endif

using namespace cv;
using namespace std;

// Static OCR instance
static DdrocrInstance *instance = nullptr;

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

// Helper function to convert std::string to char* (caller must free the result)
static char *allocCString(const std::string &s)
{
    size_t len = s.length();
    char *buf = (char *)malloc(len + 1);
    memcpy(buf, s.c_str(), len + 1);
    return buf;
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
        // TODO evaluate a static instance of DdrocrInstance instead of initializing with Ocrprocessor
        // For now, this lives for the lifetime of the app
        if (instance == nullptr)
        {
            instance = new DdrocrInstance(std::string(outputImgPath));
            platform_log("DdrocrInstance initialized\n");
        }

        long long start = get_now();
        Mat img = imread(inputImagePath);
        if (img.empty())
        {
            platform_log("Could not open or find the image: %s\n", inputImagePath);
            return;
        }
        ProcessImgResult result = instance->process_image(img);
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
        outStrings->score = allocCString(ocr.score.text);
        outStrings->marvelous = allocCString(ocr.marvelous.text);
        outStrings->perfect = allocCString(ocr.perfect.text);
        outStrings->great = allocCString(ocr.great.text);
        outStrings->good = allocCString(ocr.good.text);
        outStrings->miss = allocCString(ocr.miss.text);
        outStrings->flare = allocCString(ocr.flare.text);
        outStrings->title = allocCString(ocr.title.text);
        outStrings->username = allocCString(ocr.username.text);
        outStrings->difficulty = allocCString(ocr.difficulty.text);
        outStrings->maxCombo = allocCString(ocr.max_combo.text);
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
        if (instance == nullptr)
        {
            instance = new DdrocrInstance(std::string(outputImgPath));
            platform_log("DdrocrInstance initialized\n");
        }

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

        if (img.empty())
        {
            platform_log("Could not open or find the image: %s\n", outputImgPath);
        }

        platform_log("Saved input image to %s\n", outputImgPath);
        try
        {
            ProcessImgResult result = instance->process_image(img);
            if (!result.isDetected)
            {
                platform_log("No OCR region detected, skipping saving processed image.\n");
                *outputIsDetected = result.isDetected;
                return;
            }
            platform_log("Saved processed image to %s\n", outputImgPath);
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
