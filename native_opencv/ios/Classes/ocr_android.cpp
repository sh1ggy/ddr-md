#ifdef __ANDROID__

#include <leptonica/allheaders.h>
#include <tesseract/baseapi.h>

typedef void *tess_api_ptr_t;
typedef void *pix_image_ptr_t;


#include "ocr_wrapper.h"

OCRResult OCRWrapper::performOCR(const cv::Mat& roiMat)
{
    OCRResult result;
    
    // Create a Pix image from the raw data
    pix_image_ptr_t pixImage = pixCreate(roiMat.cols, roiMat.rows, 8 * roiMat.channels());
    pixSetData(pixImage, (l_uint32 *)roiMat.data);
    
    // Initialize Tesseract API
    tess_api_ptr_t api = new tesseract::TessBaseAPI();
    if (api->Init(NULL, "eng"))
    {
        platform_log("Could not initialize tesseract.\n");
        return {};
    }
    
    // Set the image for OCR
    api->SetImage((Pix *)pixImage);
    
    // Perform OCR 
    char *outText = api->GetUTF8Text();
    result.text = std::string(outText);
    result.confidence = api->MeanTextConf() / 100.0f; //

    pixDestroy(&pixImage);
    // Clean up
    api->End();
    return result;
}

#endif