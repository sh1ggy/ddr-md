#ifndef DETAILS_DETECTOR_H
#define DETAILS_DETECTOR_H

#include <opencv2/opencv.hpp>
#include <string>
#include <vector>

// Single-responsibility classifier for the "Details" badge in a DDR score
// screen. Given a set of HSV-blob candidate rectangles from the input frame,
// picks which (if any) is the Details badge by template matching against a
// stored reference crop.
//
// This intentionally does NOT use any OCR model. Earlier pipelines used
// Tesseract (eng.fast PSM_SINGLE_WORD) or PaddleOCR rec to recognise the
// literal text "Details" — both were expensive and accuracy-fragile for what
// is essentially a fixed, visually-constant UI element. cv::matchTemplate at
// a handful of scales is faster, deterministic, and trivially debuggable.
//
// Usage:
//   DetailsDetector det(dataPath);            // loads template from disk
//   auto match = det.classify(inputImg, candidates);
//   if (match.index >= 0) {
//       // candidates[match.index] is the Details badge
//   }
class DetailsDetector
{
public:
    struct Match
    {
        int   index;       // index into the candidate list, -1 if no match
        float score;       // best normalised correlation (0..1) — TM_CCOEFF_NORMED
        float scale;       // template scale used for the winning match
    };

    // dataPath is the app's writable data directory (same one the Paddle
    // models live under). The constructor looks for:
    //   <dataPath>/templates/details.png
    // If absent, hasTemplate() returns false and classify() always returns
    // {-1, 0.f, 0.f} — caller can fall back.
    explicit DetailsDetector(const std::string &dataPath);

    bool hasTemplate() const { return !templateGray.empty(); }

    // Examine each candidate rectangle in inputImg and return the best
    // template match across them. Returns {-1, ...} if no candidate scores
    // above `minScore`.
    Match classify(const cv::Mat &inputImg,
                   const std::vector<cv::Rect> &candidates,
                   float minScore = 0.55f) const;

    // Optional debug directory — when set, per-candidate match scores and
    // best-scale crops get written here.
    std::string debugDir;

private:
    cv::Mat templateGray; // grayscale, single-channel template
    std::string dataPath;
};

#endif // DETAILS_DETECTOR_H
