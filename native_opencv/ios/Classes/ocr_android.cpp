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

OCRResult OCRWrapper::performOCR(const cv::Mat& roiMat)
{
    OCRResult result;

    // Create a Pix image from the raw data. `pixCreate` allocates its own
    // buffer; we then copy the pixels from the OpenCV matrix into that buffer.
    // If we instead pointed Pix at roiMat.data and later called pixDestroy,
    // the Mat's memory would be freed prematurely, leading to exactly the
    // crash seen earlier (invalid chunk state in Mat::~Mat).  So copying is
    // safer.
    
    // pix_image_ptr_t pixImage = pixCreate(roiMat.cols, roiMat.rows, 8 * roiMat.channels());
    // pixSetData(pixImage, (l_uint32 *)roiMat.data);
    
    Pix *pixImage = pixCreate(roiMat.cols, roiMat.rows, 8 * roiMat.channels());
    if (!pixImage) {
        platform_log("pixCreate failed\n");
        return {};
    }
    // copy pixel data into the pix structure
    size_t imageSize = roiMat.total() * roiMat.elemSize();
    l_uint32 *pData = pixGetData(pixImage);
    if (pData && roiMat.data) {
        memcpy(pData, roiMat.data, imageSize);
    } else {
        platform_log("failed to obtain pix data pointer\n");
        pixDestroy(&pixImage);
        return {};
    }

    // Initialize Tesseract API
    tesseract::TessBaseAPI *api = new tesseract::TessBaseAPI();
    if (api->Init(nullptr, "eng"))
    {
        platform_log("Could not initialize tesseract.\n");
        delete api;
        pixDestroy(&pixImage);
        return {};
    }

    // Set the image for OCR
    api->SetImage(pixImage);

    // Perform OCR
    char *outText = api->GetUTF8Text();
    if (outText) {
        result.text = std::string(outText);
        delete[] outText; // GetUTF8Text allocates with new[]
    }
    result.confidence = api->MeanTextConf() / 100.0f;

    pixDestroy(&pixImage); // frees the buffer we allocated inside pixCreate
    // Clean up
    api->End();
    delete api;
    return result;
}

#endif
