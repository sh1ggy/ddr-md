
// This is just to get intellisense
// #define __ANDROID__

#include <cstring>
#include <string>

// On Android the leptonica headers are installed directly in the include
// path by the CMake script (see native_opencv/android/CMakeLists.txt). The
// original code assumed a "leptonica/" subdirectory, but its sources live
// at
//     android/src/main/cpp/leptonica/src/src
// so the headers are referenced as just <allheaders.h>.
// On iOS, the podspec adds libs/include/leptonica to the header search
// path, so we also use <allheaders.h>.
#include <allheaders.h>
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
    // Suppress Leptonica TIFF/bmf warnings (no TIFF support on iOS, bitmap fonts not needed for OCR)
    setMsgSeverity(L_SEVERITY_NONE);
    // Initialize tesseract-ocr with English, without specifying tessdata path
    if (api->Init(tessdataPath.c_str(), "eng.best", tesseract::OEM_LSTM_ONLY))
    {
        platform_log("Could not initialize tesseract.\n");
        delete api;
        return;
    }
    setMsgSeverity(L_SEVERITY_ERROR);

    this->api = api;
    this->dataPath = dataPath;
    platform_log("OCRWrapper initialized\n");
}

OCRWrapper::~OCRWrapper()
{
    platform_log("OCRWrapper destroyed\n");
}

OCRResult OCRWrapper::performOCR(const cv::Mat &roiMat, OCRType type, const std::string &roiName)
{
    OCRResult result;
    result.text = "";
    result.confidence = 0.0f;
    result.boundingBox = cv::Rect(0, 0, roiMat.cols, roiMat.rows);

    if (!api)
    {
        platform_log("[OCR][%s] ERROR: api not initialized\n", roiName.c_str());
        return result;
    }

    if (roiMat.empty())
    {
        platform_log("[OCR][%s] ERROR: empty ROI input\n", roiName.c_str());
        return result;
    }

    // Input from getPreprocessedRoiImage is already a clean logical 0/1 image
    // (single-channel CV_8U, dark text on light background). Skip redundant binarization.
    if (roiMat.channels() != 1 || roiMat.depth() != CV_8U)
    {
        platform_log("[OCR][%s] ERROR: unexpected format channels=%d depth=%d\n",
                     roiName.c_str(), roiMat.channels(), roiMat.depth());
        return result;
    }

    cv::Mat logical = roiMat;
    double minVal = 0.0;
    double maxVal = 0.0;
    cv::minMaxLoc(logical, &minVal, &maxVal);

    platform_log("[OCR][%s] INPUT: type=%s size=%dx%d min=%.0f max=%.0f\n",
                 roiName.c_str(), ocrTypeToString(type),
                 logical.cols, logical.rows, minVal, maxVal);

    // Configure whitelist per type
    if (type == OCRType::Digit)
    {
        api->SetVariable("tessedit_char_whitelist", "0123456789,");
    }
    else if (type == OCRType::Eng)
    {
        // TODO: still tune this. 
        // psm word for tesseract fast
        // psm single block tesseract best
        api->SetPageSegMode(static_cast<tesseract::PageSegMode>(psm_eng));
        api->SetVariable("tessedit_char_whitelist", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz");
    }
    else if (type == OCRType::EngJP)
    {
        api->SetPageSegMode(static_cast<tesseract::PageSegMode>(psm_engjp));
        api->SetVariable("tessedit_char_whitelist", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzあいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん");
    }

    // Set DPI to 300 to match Tesseract's training data expectations
    api->SetVariable("user_defined_dpi", "300");

    // Debug: save per-ROI image just before sending to Tesseract
    if (!debugDir.empty())
    {
        cv::Mat debugImg = logical * 255;
        char debugPath[512];
        snprintf(debugPath, sizeof(debugPath), "%s/ocr_input_%s.png",
                 debugDir.c_str(), roiName.c_str());
        cv::imwrite(std::string(debugPath), debugImg);
        platform_log("[OCR][%s] saved: %s\n", roiName.c_str(), debugPath);
    }

    Pix *pixImage = pixCreate(logical.cols, logical.rows, 1);
    if (!pixImage)
    {
        platform_log("[OCR][%s] ERROR: pixCreate failed\n", roiName.c_str());
        return result;
    }

    // Copy row by row, respecting both OpenCV and Pix strides
    l_uint32 *pixData = pixGetData(pixImage);
    l_int32 wpl = pixGetWpl(pixImage);

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

    if (type == OCRType::Digit)
    {
        api->SetPageSegMode(tesseract::PSM_SINGLE_WORD);
    }

    api->SetImage(pixImage);
    char *outText = api->GetUTF8Text();
    result.text = outText ? std::string(outText) : "";
    result.confidence = static_cast<float>(api->MeanTextConf()) / 100.0f;

    // Trim trailing whitespace/newlines from OCR output
    while (!result.text.empty() && (result.text.back() == '\n' || result.text.back() == ' '))
        result.text.pop_back();

    platform_log("[OCR][%s] RESULT: text='%s' conf=%.1f%% type=%s size=%dx%d\n",
                 roiName.c_str(), result.text.c_str(),
                 result.confidence * 100.0f, ocrTypeToString(type),
                 logical.cols, logical.rows);

    // Destroy used object and release memory
    pixDestroy(&pixImage);
    delete[] outText;
    return result;
}
