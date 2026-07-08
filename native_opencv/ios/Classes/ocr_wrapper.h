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
    // The literal image handed to the rec model (after resize_norm to 48px
    // height, before tensorisation). Debug payload for the overlay's rec
    // panel; cheap refcounted header, never marshalled over FFI.
    cv::Mat recInput;
};

enum class OCRType { Eng, Digit, EngJP, Details };

// One detected text line: rectangle inside the input region + recognised text.
struct DetectedText
{
    cv::Rect box;     // axis-aligned box in input region coordinates
    OCRResult result; // text + confidence from the recogniser
};

// Selects which rec/det/dict files (relative to dataPath/models) to load.
// When null is passed to OCRWrapper, the built-in default triplet is used —
// keeping the app/FFI path unchanged.
struct ModelSet
{
    std::string recFile;  // e.g. "ppocr_mobile_rec.onnx"
    std::string detFile;  // e.g. "ppocr_mobile_det.onnx"
    std::string dictFile; // e.g. "ppocrv5_dict.txt"
};

class OCRWrapper
{
public:
    OCRWrapper(const std::string dataPath, const ModelSet *models = nullptr);
    ~OCRWrapper();

    OCRResult performOCR(const cv::Mat& roiMat, OCRType type = OCRType::Eng, const std::string& roiName = "unknown");

    // Runs the PaddleOCR detection model over regionMat, then the recognition
    // model on each detected box. Returns one DetectedText per detected line,
    // in no particular order. Boxes are in regionMat coordinates.
    std::vector<DetectedText> performDetectAndRecognise(
        const cv::Mat& regionMat,
        OCRType recType = OCRType::Eng,
        const std::string& regionName = "combined");

    std::string dataPath;
    std::string debugDir;

private:
    std::unique_ptr<Ort::Env>     env;
    std::unique_ptr<Ort::Session> session;     // recognition
    std::unique_ptr<Ort::Session> detSession;  // detection (DBNet, PP-OCR mobile det)
    std::vector<std::string>      charList;
};

#endif
