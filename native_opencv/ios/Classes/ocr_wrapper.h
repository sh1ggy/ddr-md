#ifndef OCR_WRAPPER_H
#define OCR_WRAPPER_H

#include <string>

// Save Apple's NO macro definition if it exists
#ifdef NO
#define APPLE_NO_DEFINED
#undef NO
#endif

#include <opencv2/opencv.hpp>

#if defined(__ANDROID__)
#include <tesseract/baseapi.h>
#endif

// Restore Apple's NO macro after OpenCV
#ifdef APPLE_NO_DEFINED
#define NO (BOOL)0
#endif

struct OCRResult
{
    std::string text;
    float confidence;
    cv::Rect boundingBox;
};


enum class OCRType { Eng, Digit, EngJP };

class OCRWrapper
{
public:
    OCRWrapper(const std::string dataPath = "");
    ~OCRWrapper();
    
    OCRResult performOCR(const cv::Mat& roiMat, OCRType type = OCRType::Eng);

    #if defined(__ANDROID__)
    std::string dataPath;
    tesseract::TessBaseAPI *api;
    #endif
};

#endif

/*
--- NOTE ---
Since both vision and tesseract suuport ROIS 
https://tesseract-ocr.github.io/tessdoc/Examples_C++.html

https://developer.apple.com/documentation/Vision/extracting-phone-numbers-from-text-in-images

*/
