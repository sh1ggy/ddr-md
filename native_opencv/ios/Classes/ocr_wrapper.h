#ifndef OCR_WRAPPER_H
#define OCR_WRAPPER_H

#include <string>

// Save Apple's NO macro definition if it exists
#ifdef NO
#define APPLE_NO_DEFINED
#undef NO
#endif

#include <opencv2/opencv.hpp>

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

class OCRWrapper
{
public:
    static OCRResult performOCR(const uint8_t *data, int width, int height,
                                int step, int channels);
};

#endif
