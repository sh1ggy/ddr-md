#ifdef __ANDROID__

// On Android the leptonica headers are installed directly in the include
// path by the CMake script (see native_opencv/android/CMakeLists.txt). The
// original code assumed a "leptonica/" subdirectory, but its sources live
// at
//     android/src/main/cpp/leptonica/src/src
// so the headers are referenced as just <allheaders.h>.
#include <allheaders.h>
#include <tesseract/baseapi.h>

// `platform_log` is defined in native_opencv.cpp; we need a declaration so
// this translation unit compiles.
extern void platform_log(const char *fmt, ...);

#include "ocr_wrapper.h"

OCRWrapper::OCRWrapper(const string dataPath)
{
    platform_log("OCRWrapper initialized\n");

    //TODO add in jp 
    tesseract::TessBaseAPI *api = new tesseract::TessBaseAPI();
    // Initialize tesseract-ocr with English, without specifying tessdata path
    if (api->Init(dataPath.c_str(), "eng", tesseract::OEM_LSTM_ONLY))
    {
        platform_log("Could not initialize tesseract.\n");
        delete api;
        return;
    }
    
    this.api = api;
    this.tessdataPath = dataPath;
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

    if (api->Init(tessdataPath.c_str(), "eng", tesseract::OEM_LSTM_ONLY))
    {
        platform_log("Could not initialize tesseract.\n");
        return result;
    }
    // api->SetPageSegMode(tesseract::PSM_SINGLE_LINE);
    // api->SetPageSegMode(tesseract::PSM_SINGLE_BLOCK);
    if (type == OCRType::Digit)
    {
        api->SetPageSegMode(tesseract::PSM_SINGLE_BLOCK);
        api->SetVariable("tessedit_char_whitelist", "0123456789");
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

    Pix *pixImage = pixCreate(roiMat.cols, roiMat.rows, 8);
    if (!pixImage)
    {
        platform_log("pixCreate failed\n");
        api->End();
        delete api;
        return result;
    }

    // Copy row by row, respecting both OpenCV and Pix strides
    l_uint32 *pixData = pixGetData(pixImage);
    l_int32 wpl = pixGetWpl(pixImage);
    l_int32 pixRowBytes = wpl * sizeof(l_uint32);

    for (int row = 0; row < roiMat.rows; ++row)
    {
        l_uint8 *pixRow = (l_uint8 *)pixData + row * pixRowBytes;
        const l_uint8 *matRow = roiMat.data + row * roiMat.step;
        memcpy(pixRow, matRow, roiMat.cols);
    }

    api->SetImage(pixImage);
    // Get OCR result
    char *outText = api->GetUTF8Text();
    result.text = outText ? std::string(outText) : "";
    result.confidence = static_cast<float>(api->MeanTextConf()) / 100.0f;
    if (outText)
    {
        platform_log("OCR output:\n%s", outText);
    }

    // Destroy used object and release memory
    pixDestroy(&pixImage);
    api->End();
    delete api;
    delete[] outText;
    return result;
}

#endif
