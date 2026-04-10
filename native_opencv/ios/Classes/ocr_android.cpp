
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
        api->SetPageSegMode(tesseract::PSM_SINGLE_WORD);
        api->SetVariable("tessedit_char_whitelist", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz");
    }
    else if (type == OCRType::EngJP)
    {
        api->SetPageSegMode(tesseract::PSM_SINGLE_WORD);
        api->SetVariable("tessedit_char_whitelist", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzあいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん");
    }

    // Set DPI to 300 to match Tesseract's training data expectations
    api->SetVariable("user_defined_dpi", "300");

    // Debug: save per-ROI image just before sending to Tesseract
    {
        cv::Mat debugImg = logical * 255;
        char debugPath[250];
        snprintf(debugPath, sizeof(debugPath), "%s/ocr_input_%s.png",
                 dataPath.c_str(), roiName.c_str());
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
        // Try multiple PSM modes and pick the one with highest confidence.
        // This helps with single-digit and two-digit ROIs that fail under a single mode.
        struct PsmCandidate {
            tesseract::PageSegMode mode;
            const char *name;
        };
        const PsmCandidate psmModes[] = {
            { tesseract::PSM_SINGLE_CHAR,  "SINGLE_CHAR"  },
            { tesseract::PSM_SINGLE_WORD,  "SINGLE_WORD"  },
            { tesseract::PSM_SINGLE_LINE,  "SINGLE_LINE"  },
            { tesseract::PSM_RAW_LINE,     "RAW_LINE"     },
            { tesseract::PSM_SINGLE_BLOCK, "SINGLE_BLOCK" },
        };
        const int numModes = sizeof(psmModes) / sizeof(psmModes[0]);

        float bestConf = -1.0f;
        std::string bestText;
        std::string bestSymbolDetail;
        int bestCharCount = 0;
        const char *bestModeName = "";

        for (int m = 0; m < numModes; ++m)
        {
            api->SetPageSegMode(psmModes[m].mode);
            api->SetImage(pixImage);
            api->Recognize(0);

            tesseract::ResultIterator *ri = api->GetIterator();
            tesseract::PageIteratorLevel level = tesseract::RIL_SYMBOL;

            float totalConf = 0.0f;
            int charCount = 0;
            std::string text;
            std::string symbolDetail;

            if (ri != 0)
            {
                do
                {
                    const char *symbol = ri->GetUTF8Text(level);
                    float conf = ri->Confidence(level);

                    if (symbol)
                    {
                        if (!symbolDetail.empty()) symbolDetail += ", ";
                        symbolDetail += "'" + std::string(symbol) + "'@" + std::to_string((int)conf) + "%";
                        text += std::string(symbol);
                    }
                    totalConf += conf;
                    ++charCount;

                    delete[] symbol;
                } while (ri->Next(level));
            }

            float avgConf = charCount > 0 ? totalConf / charCount : 0.0f;

            platform_log("[OCR][%s] PSM_%-12s: text='%s' avgConf=%.1f%% chars=%d symbols=[%s]\n",
                         roiName.c_str(), psmModes[m].name,
                         text.c_str(), avgConf, charCount,
                         symbolDetail.c_str());

            if (avgConf > bestConf)
            {
                bestConf = avgConf;
                bestText = text;
                bestSymbolDetail = symbolDetail;
                bestCharCount = charCount;
                bestModeName = psmModes[m].name;
            }

            api->Clear();
        }

        result.text = bestText;
        result.confidence = bestConf / 100.0f;

        platform_log("[OCR][%s] BEST: psm=%s text='%s' avgConf=%.1f%% chars=%d symbols=[%s]\n",
                     roiName.c_str(), bestModeName,
                     result.text.c_str(),
                     result.confidence * 100.0f, bestCharCount,
                     bestSymbolDetail.c_str());

        pixDestroy(&pixImage);
        return result;
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
#endif
