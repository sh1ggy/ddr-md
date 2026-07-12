#include "details_detector.h"

#include <algorithm>
#include <chrono>

extern void platform_log(const char *fmt, ...);

namespace
{
    // Template match runs at a handful of scales to handle the unknown size of
    // the badge in the input frame. The HSV blob filter narrows candidates
    // down enough that we only need to brute-force a small range.
    constexpr float MIN_SCALE = 0.6f;
    constexpr float MAX_SCALE = 1.6f;
    constexpr float SCALE_STEP = 0.1f;
}

DetailsDetector::DetailsDetector(const std::string &dataPath)
    : dataPath(dataPath)
{
    reload();
}

void DetailsDetector::reload()
{
    const std::string templatePath = dataPath + "/templates/details.png";
    cv::Mat gray = cv::imread(templatePath, cv::IMREAD_GRAYSCALE);
    if (gray.empty())
    {
        // Keep any previously loaded template rather than clobbering it with
        // an unreadable file.
        platform_log("[DETAILS_DET] template missing or unreadable: %s\n",
                     templatePath.c_str());
        return;
    }
    std::lock_guard<std::mutex> lk(templateMutex);
    templateGray = gray;
    platform_log("[DETAILS_DET] template loaded %dx%d from %s\n",
                 templateGray.cols, templateGray.rows, templatePath.c_str());
}

DetailsDetector::Match DetailsDetector::classify(
    const cv::Mat &inputImg,
    const std::vector<cv::Rect> &candidates,
    float minScore) const
{
    Match best{-1, 0.0f, 0.0f};

    // Snapshot the template so a concurrent reload() can't swap it mid-match
    // (cv::Mat copy is a cheap refcounted header copy).
    cv::Mat tmpl;
    {
        std::lock_guard<std::mutex> lk(templateMutex);
        tmpl = templateGray;
    }
    if (tmpl.empty())
    {
        platform_log("[DETAILS_DET] no template loaded — skipping classify\n");
        return best;
    }
    if (inputImg.empty() || candidates.empty())
    {
        return best;
    }

    auto t0 = std::chrono::high_resolution_clock::now();

    // Convert input to grayscale once — template is grayscale, and matching
    // on grayscale is robust to per-frame colour shifts.
    cv::Mat inputGray;
    if (inputImg.channels() == 1)
        inputGray = inputImg;
    else
        cv::cvtColor(inputImg, inputGray, cv::COLOR_BGR2GRAY);

    for (size_t i = 0; i < candidates.size(); ++i)
    {
        const cv::Rect &raw = candidates[i];
        cv::Rect roi = raw & cv::Rect(0, 0, inputGray.cols, inputGray.rows);
        if (roi.width <= 0 || roi.height <= 0) continue;

        cv::Mat candidate = inputGray(roi);

        // For each candidate, try several scales of the template. We rescale
        // the *template* (cheaper than rescaling the candidate) and stop
        // scales that no longer fit inside the candidate ROI.
        float bestForCandidate = -1.0f;
        float bestScaleForCandidate = 0.0f;

        for (float scale = MIN_SCALE; scale <= MAX_SCALE + 1e-3f; scale += SCALE_STEP)
        {
            int tw = std::max(4, (int)std::round(tmpl.cols * scale));
            int th = std::max(4, (int)std::round(tmpl.rows * scale));
            if (tw > candidate.cols || th > candidate.rows) continue;

            cv::Mat scaledTemplate;
            cv::resize(tmpl, scaledTemplate, cv::Size(tw, th),
                       0, 0, cv::INTER_AREA);

            cv::Mat heatmap;
            cv::matchTemplate(candidate, scaledTemplate, heatmap,
                              cv::TM_CCOEFF_NORMED);

            double mn, mx;
            cv::Point mnLoc, mxLoc;
            cv::minMaxLoc(heatmap, &mn, &mx, &mnLoc, &mxLoc);

            if (mx > bestForCandidate)
            {
                bestForCandidate = (float)mx;
                bestScaleForCandidate = scale;
            }
        }

        platform_log("[DETAILS_DET][cand %zu] size=%dx%d bestScore=%.3f @ scale=%.2f\n",
                     i, roi.width, roi.height, bestForCandidate, bestScaleForCandidate);

        if (bestForCandidate > best.score)
        {
            best.score = bestForCandidate;
            best.scale = bestScaleForCandidate;
            best.index = (int)i;
        }
    }

    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::high_resolution_clock::now() - t0).count();
    platform_log("[DETAILS_DET] classify: %lld ms across %zu candidates, best=%.3f minScore=%.2f\n",
                 (long long)ms, candidates.size(), best.score, minScore);

    if (best.score < minScore)
    {
        // No candidate cleared the threshold. Surface this clearly so the
        // caller can decide whether to fall back or fail.
        return Match{-1, best.score, best.scale};
    }
    return best;
}
