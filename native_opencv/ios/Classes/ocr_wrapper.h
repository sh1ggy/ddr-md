#ifndef OCR_WRAPPER_H
#define OCR_WRAPPER_H

#include <memory>
#include <string>
#include <vector>

#include <opencv2/opencv.hpp>
#include <onnxruntime_cxx_api.h>

struct OCRResult
{
    std::string text;
    float confidence;
    cv::Rect boundingBox;
};

enum class OCRType { Eng, Digit, EngJP, Details };

class OCRWrapper
{
public:
    OCRWrapper(const std::string dataPath);
    ~OCRWrapper();

    OCRResult performOCR(const cv::Mat& roiMat, OCRType type = OCRType::Eng, const std::string& roiName = "unknown");

    std::string dataPath;
    std::string debugDir;

private:
    std::unique_ptr<Ort::Env>     env;
    std::unique_ptr<Ort::Session> session;
    std::vector<std::string>      charList;
};

#endif
