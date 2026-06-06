
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
    std::string detPath   = dataPath + "/models/ppocr_mobile_det.onnx";
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
        platform_log("OCRWrapper: rec ONNX session loaded from %s\n", modelPath.c_str());
    }
    catch (const Ort::Exception &e)
    {
        platform_log("OCRWrapper: failed to load rec ONNX model: %s\n", e.what());
    }

    // Detection model is optional — if absent, performDetectAndRecognise will
    // return empty and the caller can fall back to per-ROI recognition.
    // Source: PaddleOCR PP-OCRv5_mobile_det (or PP-OCRv3_mobile_det) converted
    // to ONNX via paddle2onnx. See model card:
    //   https://huggingface.co/PaddlePaddle/PP-OCRv3_mobile_det
    // Place the .onnx at assets/models/ppocr_mobile_det.onnx and add to pubspec.
    try
    {
        detSession = std::make_unique<Ort::Session>(*env, detPath.c_str(), sessionOpts);
        platform_log("OCRWrapper: det ONNX session loaded from %s\n", detPath.c_str());
    }
    catch (const Ort::Exception &e)
    {
        platform_log("OCRWrapper: det model unavailable (%s) — det+rec disabled\n", e.what());
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

// ---------------------------------------------------------------------------
// Detection (DBNet) + recognition pipeline.
// ---------------------------------------------------------------------------
//
// Preprocessing matches PaddleOCR's official det inference:
//   - Resize so the longer side is a multiple of 32, preserving aspect ratio.
//     We use a fixed limit_side_len of 960 (PP-OCRv5 default for the mobile
//     det model); smaller inputs are not enlarged.
//   - BGR -> RGB, normalise with ImageNet mean/std (det uses ImageNet norm,
//     unlike rec which uses (x/255 - 0.5)/0.5).
//   - NCHW float32, batch=1.
//
// Output: probability map of shape [1,1,H,W]. Postprocess:
//   - Threshold (default 0.3) -> binary mask
//   - findContours -> for each contour, axis-aligned bounding rect
//   - Scale rects back to input regionMat coordinates
//   - Apply a small unclip expansion so we capture descenders/strokes
//
// Reference: PaddleOCR/tools/infer/predict_det.py + db_postprocess.py
namespace
{
    constexpr int   DET_LIMIT_SIDE_LEN = 960;
    constexpr float DET_BIN_THRESHOLD  = 0.3f;
    constexpr float DET_BOX_MIN_AREA   = 16.0f; // px^2 in det-space
    constexpr float DET_UNCLIP_RATIO   = 1.6f;

    // Resize so max(H,W) ~= limit, both rounded to a multiple of 32.
    // Returns the actual resize dims and the ratios needed to map back.
    cv::Mat detPreprocess(const cv::Mat &bgr, int limit, float &ratioH, float &ratioW)
    {
        int origH = bgr.rows;
        int origW = bgr.cols;
        float ratio = 1.0f;
        if (std::max(origH, origW) > limit)
            ratio = (float)limit / (float)std::max(origH, origW);

        int newH = std::max(32, (int)std::round(origH * ratio / 32.0f) * 32);
        int newW = std::max(32, (int)std::round(origW * ratio / 32.0f) * 32);

        cv::Mat resized;
        cv::resize(bgr, resized, cv::Size(newW, newH));

        ratioH = (float)origH / (float)newH;
        ratioW = (float)origW / (float)newW;
        return resized;
    }

    // Expand rect by unclipRatio (matches DB postprocess unclip step approx).
    // Pure axis-aligned expansion — cheaper than full polygon offset and good
    // enough for tight text lines.
    cv::Rect unclipRect(const cv::Rect &r, float unclipRatio)
    {
        // Heuristic: expand by perimeter*unclipRatio / (2*area) on each side,
        // matching the spirit of the DB unclip distance formula.
        float area = (float)(r.width * r.height);
        float peri = 2.0f * (r.width + r.height);
        if (area < 1.0f || peri < 1.0f) return r;
        float dist = unclipRatio * area / peri;
        int d = std::max(1, (int)std::round(dist));
        return cv::Rect(r.x - d, r.y - d, r.width + 2 * d, r.height + 2 * d);
    }
}

std::vector<DetectedText> OCRWrapper::performDetectAndRecognise(
    const cv::Mat &regionMat, OCRType recType, const std::string &regionName)
{
    std::vector<DetectedText> out;

    if (!detSession)
    {
        platform_log("[DET][%s] det session unavailable\n", regionName.c_str());
        return out;
    }
    if (regionMat.empty())
    {
        platform_log("[DET][%s] empty region\n", regionName.c_str());
        return out;
    }

    cv::Mat bgr;
    if (regionMat.channels() == 1)
        cv::cvtColor(regionMat, bgr, cv::COLOR_GRAY2BGR);
    else
        bgr = regionMat;

    float ratioH = 1.0f, ratioW = 1.0f;
    cv::Mat resized = detPreprocess(bgr, DET_LIMIT_SIDE_LEN, ratioH, ratioW);
    int H = resized.rows;
    int W = resized.cols;

    // Build NCHW float32 [1,3,H,W] — RGB, ImageNet normalised.
    // PaddleOCR det normalisation: mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225]
    static const float MEAN[3] = {0.485f, 0.456f, 0.406f};
    static const float STD[3]  = {0.229f, 0.224f, 0.225f};

    std::vector<float> tensor(3 * H * W);
    for (int row = 0; row < H; ++row)
    {
        const uchar *src = resized.ptr<uchar>(row);
        for (int col = 0; col < W; ++col)
        {
            // src is BGR; map to RGB channels of the tensor
            float b = src[col * 3 + 0] / 255.0f;
            float g = src[col * 3 + 1] / 255.0f;
            float r = src[col * 3 + 2] / 255.0f;
            tensor[0 * H * W + row * W + col] = (r - MEAN[0]) / STD[0];
            tensor[1 * H * W + row * W + col] = (g - MEAN[1]) / STD[1];
            tensor[2 * H * W + row * W + col] = (b - MEAN[2]) / STD[2];
        }
    }

    Ort::MemoryInfo memInfo = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    std::array<int64_t, 4> inputShape = {1, 3, H, W};
    Ort::Value inputOrt = Ort::Value::CreateTensor<float>(
        memInfo, tensor.data(), tensor.size(), inputShape.data(), inputShape.size());

    // PaddleOCR det model input/output names are "x" / "sigmoid_0.tmp_0" for
    // most exported PP-OCR det checkpoints. If your export uses different
    // names, adjust here. We discover them at runtime for robustness.
    Ort::AllocatorWithDefaultOptions alloc;
    auto inNamePtr  = detSession->GetInputNameAllocated(0, alloc);
    auto outNamePtr = detSession->GetOutputNameAllocated(0, alloc);
    const char *inputNames[]  = {inNamePtr.get()};
    const char *outputNames[] = {outNamePtr.get()};

    std::vector<Ort::Value> outputs;
    try
    {
        outputs = detSession->Run(Ort::RunOptions{nullptr},
                                  inputNames, &inputOrt, 1,
                                  outputNames, 1);
    }
    catch (const Ort::Exception &e)
    {
        platform_log("[DET][%s] inference error: %s\n", regionName.c_str(), e.what());
        return out;
    }

    auto &probT = outputs[0];
    auto probShape = probT.GetTensorTypeAndShapeInfo().GetShape();
    // Expected shape [1,1,H,W]
    if (probShape.size() != 4 || probShape[0] != 1 || probShape[1] != 1)
    {
        platform_log("[DET][%s] unexpected output rank/shape\n", regionName.c_str());
        return out;
    }
    int pH = (int)probShape[2];
    int pW = (int)probShape[3];
    const float *prob = probT.GetTensorData<float>();

    // Threshold to a binary mask at det-space resolution.
    cv::Mat mask(pH, pW, CV_8UC1);
    for (int y = 0; y < pH; ++y)
    {
        uchar *m = mask.ptr<uchar>(y);
        const float *p = prob + y * pW;
        for (int x = 0; x < pW; ++x)
            m[x] = (p[x] > DET_BIN_THRESHOLD) ? 255 : 0;
    }

    // Map det-space px -> original region px:
    //   det output size == resize size (H,W), and resize size maps back via
    //   ratioH/ratioW to original.
    float sx = (float)W / (float)pW * ratioW;
    float sy = (float)H / (float)pH * ratioH;

    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(mask, contours, cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);

    for (auto &c : contours)
    {
        if (c.size() < 3) continue;
        cv::Rect detRect = cv::boundingRect(c);
        if ((float)(detRect.width * detRect.height) < DET_BOX_MIN_AREA) continue;

        // Scale to original region coordinates.
        cv::Rect r(
            (int)std::round(detRect.x * sx),
            (int)std::round(detRect.y * sy),
            (int)std::round(detRect.width * sx),
            (int)std::round(detRect.height * sy));
        r = unclipRect(r, DET_UNCLIP_RATIO);
        r &= cv::Rect(0, 0, regionMat.cols, regionMat.rows);
        if (r.width <= 0 || r.height <= 0) continue;

        cv::Mat crop = regionMat(r);
        std::string boxName = regionName + "_" +
            std::to_string(r.x) + "_" + std::to_string(r.y);
        OCRResult rec = performOCR(crop, recType, boxName);
        rec.boundingBox = r;
        out.push_back({r, rec});
    }

    platform_log("[DET][%s] %zu boxes detected (det=%dx%d, region=%dx%d)\n",
                 regionName.c_str(), out.size(), pW, pH,
                 regionMat.cols, regionMat.rows);
    return out;
}
