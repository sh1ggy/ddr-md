#ifdef NO
#define APPLE_NO_DEFINED
#undef NO
#endif

#include <opencv2/opencv.hpp>
#include <chrono>
#include <cerrno>
#include <sys/stat.h>
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

long long int get_now()
{
    return chrono::duration_cast<std::chrono::milliseconds>(
               chrono::system_clock::now().time_since_epoch())
        .count();
}

void platform_log(const char *fmt, ...)
{
#ifdef NDEBUG
    // return;
#endif
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

// Encodes a single Mat (with the given extension, e.g. ".png"/".jpg") into a
// freshly malloc'd buffer that Dart owns and frees. Writes nullptr/0 when the
// Mat is empty.
static void encodeImage(
    const cv::Mat &img,
    const char *ext,
    uint8_t **outBuf,
    int32_t *outLen)
{
    *outBuf = nullptr;
    *outLen = 0;
    if (img.empty())
        return;

    std::vector<uchar> encoded;
    if (!cv::imencode(ext, img, encoded) || encoded.empty())
        return;

    uint8_t *buf = (uint8_t *)malloc(encoded.size());
    memcpy(buf, encoded.data(), encoded.size());
    *outBuf = buf;
    *outLen = (int32_t)encoded.size();
}

// PNG-encodes a debug Mat (lossless, so the binarized mask/crop stay crisp).
static void encodeDebugImage(
    const cv::Mat &img,
    uint8_t **outBuf,
    int32_t *outLen)
{
    encodeImage(img, ".png", outBuf, outLen);
}

// Marshal a ProcessImgResult into the FFI output pointers. The caller (Dart) owns
// and frees *outputRois and every COCRStrings char*.
static void writeResult(
    const ProcessImgResult &result,
    int32_t *outputIsDetected,
    int32_t **outputRois,
    int32_t *outputRoisCount,
    int32_t *outputDetailsRoiIndex,
    COCRStrings *outStrings)
{
    int actualCount = (int)result.rois.size();
    *outputRois = (int32_t *)malloc(sizeof(int32_t) * actualCount * 4);
    int32_t *roisPtr = *outputRois;
    for (size_t i = 0; i < result.rois.size(); i++)
    {
        roisPtr[i * 4 + 0] = result.rois[i].tl().x;
        roisPtr[i * 4 + 1] = result.rois[i].tl().y;
        roisPtr[i * 4 + 2] = result.rois[i].width;
        roisPtr[i * 4 + 3] = result.rois[i].height;
    }
    *outputRoisCount = actualCount;
    *outputIsDetected = result.isDetected;
    *outputDetailsRoiIndex = result.detailsRoiIndex;

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

// Avoiding name mangling
extern "C"
{
    FUNCTION_ATTRIBUTE
    const char *version()
    {
        return CV_VERSION;
    }

    FUNCTION_ATTRIBUTE
    void *create_ocr_instance(char *dataPath, COCRConfig *config)
    {
        DdrocrInstance *instance = new DdrocrInstance(std::string(dataPath), *config);
        platform_log("DdrocrInstance created %p\n", instance);
        return instance;
    }

    FUNCTION_ATTRIBUTE
    void destroy_ocr_instance(void *handle)
    {
        delete static_cast<DdrocrInstance *>(handle);
        platform_log("DdrocrInstance destroyed %p\n", handle);
    }

    FUNCTION_ATTRIBUTE
    void process_picked_image(
        void *handle,
        char *inputImagePath,
        int32_t *outputIsDetected,
        int32_t **outputRois,
        int32_t *outputRoisCount,
        int32_t *outputdetailsRoiIndex,
        COCRStrings *outStrings,
        int32_t side)
    {
        DdrocrInstance *instance = static_cast<DdrocrInstance *>(handle);

        Mat img = imread(inputImagePath);
        if (img.empty())
        {
            platform_log("Could not open or find the image: %s\n", inputImagePath);
            *outputIsDetected = 0;
            return;
        }
        ProcessImgResult result = instance->process_image(img, static_cast<DetectionSide>(side));
        if (!result.isDetected)
        {
            platform_log("No OCR region detected.\n");
            *outputIsDetected = result.isDetected;
            return;
        }
        writeResult(result, outputIsDetected, outputRois, outputRoisCount,
                    outputdetailsRoiIndex, outStrings);
    }

    FUNCTION_ATTRIBUTE
    void process_camera_image(
        void *handle,
        int32_t imgWidth,
        int32_t imgHeight,
        int32_t bytesPerRow,
        int32_t sensorOrientation,
        uint8_t *imgBuffer,
        int32_t *outputIsDetected,
        int32_t **outputRois,
        int32_t *outputRoisCount,
        int32_t *outputdetailsRoiIndex,
        COCRStrings *outStrings,
        int32_t debugImageType,
        uint8_t **outputDebugMask,
        int32_t *outputDebugMaskLen,
        uint8_t **outputDebugCrop,
        int32_t *outputDebugCropLen,
        uint8_t **outputCapture,
        int32_t *outputCaptureLen)
    {
        // Default the out-params so every early-return path leaves Dart a safe
        // (null, 0) to read.
        *outputDebugMask = nullptr;
        *outputDebugMaskLen = 0;
        *outputDebugCrop = nullptr;
        *outputDebugCropLen = 0;
        *outputCapture = nullptr;
        *outputCaptureLen = 0;

        DdrocrInstance *instance = static_cast<DdrocrInstance *>(handle);
        Mat img;

        // Plumbed from Dart for potential per-device orientation handling, but
        // not needed by the current rotation logic on either platform.
        (void)sensorOrientation;

#ifdef __ANDROID__

        // yuv is weird, see https://www.youtube.com/watch?v=q_mhF_Ys6nw
        Mat frame(imgHeight + imgHeight / 2, imgWidth, CV_8UC1, imgBuffer); // frame size: 1600x1800, frame channels: 1 , type = 0
        cvtColor(frame, img, COLOR_YUV2BGR_NV21);
        rotate(img, img, ROTATE_90_CLOCKWISE);
#else
        // Unlike Android's YUV frame (which arrives landscape and needs a 90° CW
        // rotation), the iOS BGRA frame is delivered already upright/portrait —
        // its buffer is taller than it is wide (e.g. 3024x4032). So we do NOT
        // rotate here; the pipeline (ROIs + capture) is already in portrait pixel
        // space, matching what CameraPreview shows. The optional bytesPerRow lets
        // us honour row padding when present (0 => tightly packed).
        size_t bgraStep = bytesPerRow > 0 ? (size_t)bytesPerRow : Mat::AUTO_STEP;
        Mat bgra(imgHeight, imgWidth, CV_8UC4, imgBuffer, bgraStep);
        cvtColor(bgra, img, COLOR_BGRA2BGR);
#endif

        if (img.empty())
        {
            platform_log("Camera image empty\n");
            *outputIsDetected = 0;
            return;
        }

        try
        {
            ProcessImgResult result = instance->process_image(
                img, DetectionSide::FIRST, static_cast<DebugImageType>(debugImageType));
            // Debug images can be captured even when no Details ROI is selected
            // (the full-frame mask), so emit them before the isDetected gate.
            encodeDebugImage(result.debugMask, outputDebugMask, outputDebugMaskLen);
            encodeDebugImage(result.debugDetailsCrop, outputDebugCrop, outputDebugCropLen);
            // Color capture (JPEG, lossy is fine for a display thumbnail) is only
            // ever non-empty on a successful match; emit it the same way.
            encodeImage(result.colorCapture, ".jpg", outputCapture, outputCaptureLen);
            if (!result.isDetected)
            {
                *outputIsDetected = result.isDetected;
                return;
            }
            writeResult(result, outputIsDetected, outputRois, outputRoisCount,
                        outputdetailsRoiIndex, outStrings);
            return;
        }
        catch (cv::Exception &e)
        {
            platform_log(e.what());
            *outputIsDetected = 0;
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
