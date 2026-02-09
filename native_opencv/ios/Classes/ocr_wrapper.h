#ifndef OCR_WRAPPER_H
#define OCR_WRAPPER_H

#include <string>
#include <opencv2/opencv.hpp>

struct OCRResult {
    std::string text;
    float confidence;
    cv::Rect boundingBox;
};

class OCRWrapper {
public:
    static OCRResult performOCR(const cv::Mat& image, const cv::Rect& roi);
};

#endif
