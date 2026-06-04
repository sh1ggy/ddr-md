
#include <cstring>
#include <fstream>
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>

#include <opencv2/opencv.hpp>
#include <onnxruntime_cxx_api.h>

extern void platform_log(const char *fmt, ...);

#include "ocr_wrapper.h"

// Dict indexing: blank=0, charList[i] maps to output class i+1, space=18384
static constexpr int BLANK_IDX = 0;

namespace
{
    const char *ocrTypeToString(OCRType type)
    {
        switch (type)
        {
        case OCRType::Digit:   return "Digit";
        case OCRType::Eng:     return "Eng";
        case OCRType::EngJP:   return "EngJP";
        case OCRType::Details: return "Details";
        default:               return "Unknown";
        }
    }

    // CTC greedy decode: argmax per timestep, collapse consecutive dups, remove blank.
    // Output class i maps to charList[i-1] (class 0 = blank).
    std::string ctcDecode(const float *logits, int seqLen, int numClasses,
                          const std::vector<std::string> &charList,
                          float &outConfidence)
    {
        std::string text;
        float confSum = 0.0f;
        int confCount = 0;
        int prevIdx = -1;

        for (int t = 0; t < seqLen; ++t)
        {
            const float *row = logits + t * numClasses;
            int best = static_cast<int>(std::max_element(row, row + numClasses) - row);

            if (best != BLANK_IDX && best != prevIdx)
            {
                int charIdx = best - 1;
                text += (charIdx >= 0 && charIdx < (int)charList.size())
                        ? charList[charIdx]
                        : " ";

                // Softmax probability of the winning class
                float maxLogit = row[best];
                float sumExp = 0.0f;
                for (int c = 0; c < numClasses; ++c)
                    sumExp += std::exp(row[c] - maxLogit);
                confSum += 1.0f / sumExp;
                ++confCount;
            }
            prevIdx = best;
        }

        outConfidence = confCount > 0 ? confSum / confCount : 0.0f;
        return text;
    }

    void rtrim(std::string &s)
    {
        while (!s.empty() && (s.back() == '\n' || s.back() == ' ' || s.back() == '\r'))
            s.pop_back();
    }

    // Post-process: strip non-digits for numeric fields
    void postProcess(std::string &text, OCRType type)
    {
        if (type != OCRType::Digit) return;
        std::string out;
        for (char c : text)
            if ((c >= '0' && c <= '9') || c == ',')
                out += c;
        text = out;
    }
}

OCRWrapper::OCRWrapper(const std::string dataPath)
    : dataPath(dataPath)
{
    std::string modelPath = dataPath + "/models/ppocr_mobile_rec.onnx";
    std::string dictPath  = dataPath + "/models/ppocrv5_dict.txt";

    std::ifstream dictFile(dictPath);
    if (!dictFile.is_open())
    {
        platform_log("OCRWrapper: failed to open dict: %s\n", dictPath.c_str());
        return;
    }
    std::string line;
    while (std::getline(dictFile, line))
        charList.push_back(line);
    platform_log("OCRWrapper: loaded dict with %zu chars\n", charList.size());

    env = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "ddrocr");
    Ort::SessionOptions sessionOpts;
    sessionOpts.SetIntraOpNumThreads(2);
    sessionOpts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

    try
    {
        session = std::make_unique<Ort::Session>(*env, modelPath.c_str(), sessionOpts);
        platform_log("OCRWrapper: ONNX session loaded from %s\n", modelPath.c_str());
    }
    catch (const Ort::Exception &e)
    {
        platform_log("OCRWrapper: failed to load ONNX model: %s\n", e.what());
    }
}

OCRWrapper::~OCRWrapper()
{
    platform_log("OCRWrapper destroyed\n");
}

OCRResult OCRWrapper::performOCR(const cv::Mat &roiMat, OCRType type, const std::string &roiName)
{
    OCRResult result;
    result.text       = "";
    result.confidence = 0.0f;
    result.boundingBox = cv::Rect(0, 0, roiMat.cols, roiMat.rows);

    if (!session)
    {
        platform_log("[OCR][%s] ERROR: session not initialized\n", roiName.c_str());
        return result;
    }
    if (roiMat.empty())
    {
        platform_log("[OCR][%s] ERROR: empty ROI\n", roiName.c_str());
        return result;
    }

    // --- Preprocessing (matches PP-OCRv5 resize_norm_img) ---
    // Accepts BGR (3ch) or grayscale (1ch) uint8.
    // Output: float32 BGR NCHW [1,3,48,320], (x/255 - 0.5)/0.5, right-padded with -1.0.

    static constexpr int TARGET_H = 48;
    static constexpr int TARGET_W = 320;

    // Ensure BGR uint8
    cv::Mat bgr;
    if (roiMat.channels() == 1)
        cv::cvtColor(roiMat, bgr, cv::COLOR_GRAY2BGR);
    else if (roiMat.channels() == 3)
        bgr = roiMat;
    else
    {
        platform_log("[OCR][%s] ERROR: unexpected channels=%d\n", roiName.c_str(), roiMat.channels());
        return result;
    }
    if (bgr.depth() != CV_8U)
    {
        platform_log("[OCR][%s] ERROR: expected CV_8U, got depth=%d\n", roiName.c_str(), bgr.depth());
        return result;
    }

    // Resize: height=48, preserve aspect ratio, cap width at 320
    int resizedW = std::min(TARGET_W, std::max(1, static_cast<int>(bgr.cols * TARGET_H / (float)bgr.rows)));
    cv::Mat resized;
    cv::resize(bgr, resized, cv::Size(resizedW, TARGET_H), 0, 0, cv::INTER_LINEAR);

    // Build NCHW float32 tensor [1,3,48,320].
    // Padding fill = (0/255 - 0.5)/0.5 = -1.0 (black, background for a typical text image)
    int H = TARGET_H, W = TARGET_W;
    std::vector<float> inputTensor(3 * H * W, -1.0f);
    for (int c = 0; c < 3; ++c)
    {
        for (int row = 0; row < H; ++row)
        {
            const uchar *srcRow = resized.ptr<uchar>(row);
            float *dstRow = inputTensor.data() + c * H * W + row * W;
            for (int col = 0; col < resizedW; ++col)
                dstRow[col] = (srcRow[col * 3 + c] / 255.0f - 0.5f) / 0.5f;
        }
    }

    // --- Inference ---
    Ort::MemoryInfo memInfo = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    std::array<int64_t, 4> inputShape = {1, 3, H, W};
    Ort::Value inputOrt = Ort::Value::CreateTensor<float>(
        memInfo, inputTensor.data(), inputTensor.size(), inputShape.data(), inputShape.size());

    const char *inputNames[]  = {"x"};
    const char *outputNames[] = {"fetch_name_0"};

    std::vector<Ort::Value> outputs;
    try
    {
        outputs = session->Run(Ort::RunOptions{nullptr},
                               inputNames, &inputOrt, 1,
                               outputNames, 1);
    }
    catch (const Ort::Exception &e)
    {
        platform_log("[OCR][%s] inference error: %s\n", roiName.c_str(), e.what());
        return result;
    }

    // --- Decode ---
    auto &outTensor  = outputs[0];
    auto outShape    = outTensor.GetTensorTypeAndShapeInfo().GetShape();
    int seqLen       = static_cast<int>(outShape[1]);
    int numClasses   = static_cast<int>(outShape[2]);
    const float *logits = outTensor.GetTensorData<float>();

    float conf = 0.0f;
    std::string text = ctcDecode(logits, seqLen, numClasses, charList, conf);
    rtrim(text);
    postProcess(text, type);

    result.text       = text;
    result.confidence = conf;

    if (!debugDir.empty())
    {
        char debugPath[512];
        snprintf(debugPath, sizeof(debugPath), "%s/ocr_input_%s.png",
                 debugDir.c_str(), roiName.c_str());
        cv::imwrite(std::string(debugPath), resized);
        platform_log("[OCR][%s] saved debug: %s\n", roiName.c_str(), debugPath);
    }

    platform_log("[OCR][%s] RESULT: text='%s' conf=%.1f%% type=%s size=%dx%d\n",
                 roiName.c_str(), result.text.c_str(),
                 result.confidence * 100.0f, ocrTypeToString(type),
                 roiMat.cols, roiMat.rows);

    return result;
}
