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
        ProcessImgResult result = instance->process_image(
            img, static_cast<DetectionSide>(side), DebugImageType::ON);
        if (!result.isDetected)
        {
            platform_log("No OCR region detected.\n");
            *outputIsDetected = result.isDetected;
            return;
        }
        writeResult(result, outputIsDetected, outputRois, outputRoisCount,
                    outputdetailsRoiIndex, outStrings);
    }
}
