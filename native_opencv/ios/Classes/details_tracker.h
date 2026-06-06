#pragma once

#include <opencv2/opencv.hpp>
#include <vector>

// KLT + RANSAC homography tracker that carries the Details box quad across
// frames where the HSV/Tesseract detector misses. Refreshed on every
// successful detection so drift never compounds beyond a single dropout streak.
class DetailsTracker
{
public:
    // Re-anchor to a fresh detection. quad must be 4 corners ordered
    // tl, tr, br, bl (matching the convex-hull ordering already produced in
    // DdrocrInstance::process_image).
    void refresh(const cv::Mat &grayFrame, const std::vector<cv::Point2f> &quad);

    // Returns the projected quad for grayFrame, or an empty vector when there
    // is no valid anchor / tracking failed (too few KLT survivors, too few
    // RANSAC inliers, or the consecutive-miss limit was hit).
    std::vector<cv::Point2f> project(const cv::Mat &grayFrame);

    bool isValid() const { return valid_; }
    void invalidate();

private:
    cv::Mat prevGray_;
    std::vector<cv::Point2f> prevFeatures_;
    std::vector<cv::Point2f> anchorQuad_;
    int missCount_ = 0;
    bool valid_ = false;

    static constexpr int kMaxConsecutiveMisses = 15;
    static constexpr int kMinSurvivingFeatures = 8;
    static constexpr double kMinInlierRatio = 0.5;
    static constexpr int kMaxFeatures = 200;
    static constexpr double kFeatureQuality = 0.01;
    static constexpr double kFeatureMinDistance = 8.0;
    static constexpr double kRansacReprojThreshold = 3.0;
};
