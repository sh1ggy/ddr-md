
// This is just to get intellisense
// #define __ANDROID__

#ifdef __ANDROID__

#include <cstring>
#include <string>

// On Android the leptonica headers are installed directly in the include
// path by the CMake script (see native_opencv/android/CMakeLists.txt). The
// original code assumed a "leptonica/" subdirectory, but its sources live
// at
//     android/src/main/cpp/leptonica/src/src
// so the headers are referenced as just <allheaders.h>.
#ifdef __ANDROID__
#include <allheaders.h>
#else
#include <leptonica/allheaders.h>
#endif
#include <tesseract/baseapi.h>

// `platform_log` is defined in native_opencv.cpp; we need a declaration so
// this translation unit compiles.
extern void platform_log(const char *fmt, ...);

#include "ocr_wrapper.h"
namespace
{
    const char *ocrTypeToString(OCRType type)
    {
        switch (type)
        {
        case OCRType::Digit:
            return "Digit";
        case OCRType::Eng:
            return "Eng";
        case OCRType::EngJP:
            return "EngJP";
        default:
            return "Unknown";
        }
    }

    std::string cvMatTypeToString(int type)
    {
        const int depth = type & CV_MAT_DEPTH_MASK;
        const int chans = 1 + (type >> CV_CN_SHIFT);

        std::string depthStr;
        switch (depth)
        {
        case CV_8U:
            depthStr = "CV_8U";
            break;
        case CV_8S:
            depthStr = "CV_8S";
            break;
        case CV_16U:
            depthStr = "CV_16U";
            break;
        case CV_16S:
            depthStr = "CV_16S";
            break;
        case CV_32S:
            depthStr = "CV_32S";
            break;
        case CV_32F:
            depthStr = "CV_32F";
            break;
        case CV_64F:
            depthStr = "CV_64F";
            break;
        case CV_16F:
            depthStr = "CV_16F";
            break;
        default:
            depthStr = "CV_Unknown";
            break;
        }

        return depthStr + "C" + std::to_string(chans);
    }
}

OCRWrapper::OCRWrapper(const std::string dataPath)
{
    std::string tessdataPath = dataPath + "/tessdata";
    // TODO add in jp
    tesseract::TessBaseAPI *api = new tesseract::TessBaseAPI();
    // Initialize tesseract-ocr with English, without specifying tessdata path
    if (api->Init(tessdataPath.c_str(), "eng", tesseract::OEM_LSTM_ONLY))
    {
        platform_log("Could not initialize tesseract.\n");
        delete api;
        return;
    }

    this->api = api;
    this->dataPath = dataPath;
    platform_log("OCRWrapper initialized\n");
}

OCRWrapper::~OCRWrapper()
{
    platform_log("OCRWrapper destroyed\n");
}

OCRResult OCRWrapper::performOCR(const cv::Mat &roiMat, OCRType type)
{
    OCRResult result;
    result.text = "";
    result.confidence = 0.0f;
    result.boundingBox = cv::Rect(0, 0, roiMat.cols, roiMat.rows);
 
    // todo: change all conditions to asserts
    if (!api)
    {
        platform_log("[OCR] api not initialized\n");
        return result;
    }

    if (roiMat.empty())
    {
        platform_log("[OCR] empty ROI input\n");
        return result;
    }

    cv::Mat grayInput;
    if (roiMat.channels() == 1)
    {
        grayInput = roiMat;
    }
    else
    {
        cv::cvtColor(roiMat, grayInput, cv::COLOR_BGR2GRAY);
    }

    cv::Mat gray8;
    if (grayInput.depth() == CV_8U)
        gray8 = grayInput;
    else
        grayInput.convertTo(gray8, CV_8U);

    cv::Mat logical;
    double minVal = 0.0;
    double maxVal = 0.0;
    cv::minMaxLoc(gray8, &minVal, &maxVal);
    if (maxVal <= 1.0)
    {
        logical = gray8;
    }
    else
    {
        cv::Mat binary255;
        cv::threshold(gray8, binary255, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);
        binary255.convertTo(logical, CV_8U, 1.0 / 255.0);
    }

    cv::minMaxLoc(logical, &minVal, &maxVal);

    platform_log("[OCR][INPUT] type=%s rows=%d cols=%d channels=%d depth=%d elemSize=%zu elemSize1=%zu total=%zu step=%zu step1=%zu isContinuous=%d cvType=%d(%s) min=%.1f max=%.1f\n",
                 ocrTypeToString(type),
                 logical.rows,
                 logical.cols,
                 logical.channels(),
                 logical.depth(),
                 logical.elemSize(),
                 logical.elemSize1(),
                 logical.total(),
                 logical.step,
                 logical.step1(),
                 logical.isContinuous() ? 1 : 0,
                 logical.type(),
                 cvMatTypeToString(logical.type()).c_str(),
                 minVal,
                 maxVal);

    // api->SetPageSegMode(tesseract::PSM_SINGLE_LINE);
    // api->SetPageSegMode(tesseract::PSM_SINGLE_BLOCK);
    if (type == OCRType::Digit)
    {
        // Use single character mode for improved digit recognition
        api->SetPageSegMode(tesseract::PSM_RAW_LINE);
        api->SetVariable("tessedit_char_whitelist", "0123456789,");
       
        return result;
    }
    else if (type == OCRType::Eng)
    {
        api->SetPageSegMode(tesseract::PSM_SINGLE_WORD);
        api->SetVariable("tessedit_char_whitelist", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz");
    }
    else if (type == OCRType::EngJP)
    {
        api->SetPageSegMode(tesseract::PSM_SINGLE_WORD);
        api->SetVariable("tessedit_char_whitelist", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzあいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん");
    }

    Pix *pixImage = pixCreate(logical.cols, logical.rows, 1);
    if (!pixImage)
    {
        platform_log("pixCreate failed\n");
        return result;
    }

    // Copy row by row, respecting both OpenCV and Pix strides
    l_uint32 *pixData = pixGetData(pixImage);
    l_int32 wpl = pixGetWpl(pixImage);
    l_int32 pixRowBytes = wpl * sizeof(l_uint32);
    const l_int32 pixDepth = pixGetDepth(pixImage);
    const l_int32 pixWidth = pixGetWidth(pixImage);
    const l_int32 pixHeight = pixGetHeight(pixImage);

    platform_log("[OCR][PIX] width=%d height=%d depth=%d wpl=%d rowBytes=%d inputStep=%zu\n",
                 pixWidth,
                 pixHeight,
                 pixDepth,
                 wpl,
                 pixRowBytes,
                 logical.step);

    for (int row = 0; row < logical.rows; ++row)
    {
        l_uint32 *line = pixData + row * wpl;
        const l_uint8 *matRow = logical.data + row * logical.step;
        for (int col = 0; col < logical.cols; ++col)
        {
            if (matRow[col] != 0)
            {
                SET_DATA_BIT(line, col);
            }
        }
    }

    api->SetImage(pixImage);
    // Get OCR result

    // TO TEST slowdown here?
    char *outText = api->GetUTF8Text();
    result.text = outText ? std::string(outText) : "";
    result.confidence = static_cast<float>(api->MeanTextConf()) / 100.0f;
    const int confRaw = api->MeanTextConf();

    const size_t textLen = result.text.size();
    platform_log("[OCR][OUTPUT] confRaw=%d conf=%.3f textLen=%zu text=%s\n",
                 confRaw,
                 result.confidence,
                 textLen,
                 result.text.c_str());

    if (outText)
    {
        platform_log("OCR output:\n%s", outText);
    }

    // TO TEST slowdown here?

    // Destroy used object and release memory
    pixDestroy(&pixImage);
    delete[] outText;
    return result;
}
#endif
