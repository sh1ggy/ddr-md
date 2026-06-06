#include "details_tracker.h"

extern void platform_log(const char *fmt, ...);

void DetailsTracker::invalidate()
{
    prevGray_.release();
    prevFeatures_.clear();
    anchorQuad_.clear();
    missCount_ = 0;
    valid_ = false;
}

void DetailsTracker::refresh(const cv::Mat &grayFrame, const std::vector<cv::Point2f> &quad)
{
    platform_log("[TRACKER] refresh CALLED, frame=%dx%d, quad.size=%zu\n",
                 grayFrame.cols, grayFrame.rows, quad.size());
    if (grayFrame.empty() || quad.size() != 4)
    {
        platform_log("[TRACKER] refresh: bad input (empty=%d), invalidating\n",
                     grayFrame.empty() ? 1 : 0);
        invalidate();
        return;
    }
    platform_log("[TRACKER] refresh quad corners: tl=(%.1f,%.1f) tr=(%.1f,%.1f) br=(%.1f,%.1f) bl=(%.1f,%.1f)\n",
                 quad[0].x, quad[0].y, quad[1].x, quad[1].y,
                 quad[2].x, quad[2].y, quad[3].x, quad[3].y);

    cv::Mat mask = cv::Mat::zeros(grayFrame.size(), CV_8UC1);
    std::vector<cv::Point> intQuad;
    intQuad.reserve(4);
    for (const auto &p : quad)
        intQuad.emplace_back(cv::Point((int)p.x, (int)p.y));
    cv::fillConvexPoly(mask, intQuad, cv::Scalar(255));

    std::vector<cv::Point2f> features;
    cv::goodFeaturesToTrack(grayFrame, features, kMaxFeatures, kFeatureQuality,
                            kFeatureMinDistance, mask);

    if (features.size() < kMinSurvivingFeatures)
    {
        platform_log("[TRACKER] refresh: only %zu features in quad (min=%d), invalidating\n",
                     features.size(), kMinSurvivingFeatures);
        invalidate();
        return;
    }

    prevGray_ = grayFrame.clone();
    prevFeatures_ = std::move(features);
    anchorQuad_ = quad;
    missCount_ = 0;
    valid_ = true;
    platform_log("[TRACKER] refresh DONE: anchored with %zu features, valid=1\n",
                 prevFeatures_.size());
}

std::vector<cv::Point2f> DetailsTracker::project(const cv::Mat &grayFrame)
{
    platform_log("[TRACKER] project CALLED: valid=%d missCount=%d prevFeatures=%zu frame=%dx%d\n",
                 valid_ ? 1 : 0, missCount_, prevFeatures_.size(),
                 grayFrame.cols, grayFrame.rows);
    if (!valid_ || grayFrame.empty())
    {
        platform_log("[TRACKER] project: bailing early (valid=%d empty=%d)\n",
                     valid_ ? 1 : 0, grayFrame.empty() ? 1 : 0);
        return {};
    }

    if (prevGray_.size() != grayFrame.size())
    {
        platform_log("[TRACKER] frame size changed (prev=%dx%d curr=%dx%d), invalidating\n",
                     prevGray_.cols, prevGray_.rows, grayFrame.cols, grayFrame.rows);
        invalidate();
        return {};
    }

    if (missCount_ >= kMaxConsecutiveMisses)
    {
        platform_log("[TRACKER] hit %d consecutive misses (max=%d), invalidating\n",
                     missCount_, kMaxConsecutiveMisses);
        invalidate();
        return {};
    }

    std::vector<cv::Point2f> nextFeatures;
    std::vector<uchar> status;
    std::vector<float> err;
    cv::calcOpticalFlowPyrLK(prevGray_, grayFrame, prevFeatures_, nextFeatures,
                             status, err);

    std::vector<cv::Point2f> srcPts;
    std::vector<cv::Point2f> dstPts;
    srcPts.reserve(prevFeatures_.size());
    dstPts.reserve(prevFeatures_.size());
    for (size_t i = 0; i < status.size(); i++)
    {
        if (status[i])
        {
            srcPts.push_back(prevFeatures_[i]);
            dstPts.push_back(nextFeatures[i]);
        }
    }
    platform_log("[TRACKER] project KLT: %zu input -> %zu survivors\n",
                 prevFeatures_.size(), srcPts.size());

    if (srcPts.size() < kMinSurvivingFeatures)
    {
        platform_log("[TRACKER] project: only %zu KLT survivors (min=%d), invalidating\n",
                     srcPts.size(), kMinSurvivingFeatures);
        invalidate();
        return {};
    }

    std::vector<uchar> inlierMask;
    cv::Mat H = cv::findHomography(srcPts, dstPts, cv::RANSAC,
                                   kRansacReprojThreshold, inlierMask);
    if (H.empty())
    {
        platform_log("[TRACKER] project: findHomography failed, invalidating\n");
        invalidate();
        return {};
    }

    int inlierCount = 0;
    for (uchar m : inlierMask)
        if (m) inlierCount++;
    const double inlierRatio = (double)inlierCount / (double)srcPts.size();
    if (inlierRatio < kMinInlierRatio)
    {
        platform_log("[TRACKER] project: inlier ratio %.2f < %.2f, invalidating\n",
                     inlierRatio, kMinInlierRatio);
        invalidate();
        return {};
    }

    std::vector<cv::Point2f> projectedQuad;
    cv::perspectiveTransform(anchorQuad_, projectedQuad, H);
    if (projectedQuad.size() != 4)
    {
        platform_log("[TRACKER] project: perspectiveTransform returned %zu pts, invalidating\n",
                     projectedQuad.size());
        invalidate();
        return {};
    }

    platform_log("[TRACKER] project DONE: %d inliers / %zu KLT-survivors (ratio %.2f), missCount->%d\n",
                 inlierCount, srcPts.size(), inlierRatio, missCount_ + 1);
    platform_log("[TRACKER] project anchor BEFORE: tl=(%.1f,%.1f) tr=(%.1f,%.1f) br=(%.1f,%.1f) bl=(%.1f,%.1f)\n",
                 anchorQuad_[0].x, anchorQuad_[0].y, anchorQuad_[1].x, anchorQuad_[1].y,
                 anchorQuad_[2].x, anchorQuad_[2].y, anchorQuad_[3].x, anchorQuad_[3].y);
    platform_log("[TRACKER] project quad AFTER:   tl=(%.1f,%.1f) tr=(%.1f,%.1f) br=(%.1f,%.1f) bl=(%.1f,%.1f)\n",
                 projectedQuad[0].x, projectedQuad[0].y, projectedQuad[1].x, projectedQuad[1].y,
                 projectedQuad[2].x, projectedQuad[2].y, projectedQuad[3].x, projectedQuad[3].y);

    prevGray_ = grayFrame.clone();
    anchorQuad_ = projectedQuad;
    // Re-seed features from inside the newly projected quad so the next
    // projection has fresh interior coverage instead of drifting KLT chains.
    cv::Mat mask = cv::Mat::zeros(grayFrame.size(), CV_8UC1);
    std::vector<cv::Point> intQuad;
    intQuad.reserve(4);
    for (const auto &p : projectedQuad)
        intQuad.emplace_back(cv::Point((int)p.x, (int)p.y));
    cv::fillConvexPoly(mask, intQuad, cv::Scalar(255));
    std::vector<cv::Point2f> reseeded;
    cv::goodFeaturesToTrack(grayFrame, reseeded, kMaxFeatures, kFeatureQuality,
                            kFeatureMinDistance, mask);
    if (reseeded.size() < kMinSurvivingFeatures)
    {
        // Carry forward the KLT-survivor dst points instead — better than nothing
        // for the next frame, even if coverage shrinks. The miss-count cap
        // bounds how long this can chain.
        prevFeatures_ = dstPts;
    }
    else
    {
        prevFeatures_ = std::move(reseeded);
    }

    missCount_++;
    return projectedQuad;
}
