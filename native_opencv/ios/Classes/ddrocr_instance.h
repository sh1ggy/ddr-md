#pragma once

#include <opencv2/opencv.hpp>
#include <string>
#include "ocr_wrapper.h"

struct bounding_box
{
    int x1, y1, x2, y2;
    char *word;
    float confidence;
    int block_num, par_num, line_num, word_num;
};

struct bounding_boxes
{
    int length;
    struct bounding_box *boxes;
};

struct OCRResults
{
    OCRResult score;
    OCRResult marvelous;
    OCRResult perfect;
    OCRResult great;
    OCRResult good;
    OCRResult miss;
    OCRResult flare;
    OCRResult title;
    OCRResult username;
    OCRResult difficulty;
    OCRResult max_combo;
};

struct ProcessImgResult
{
    cv::Mat img;
    int32_t isDetected;
    std::vector<cv::Rect> rois;
    int32_t detailsRoiIndex;
    OCRResults ocrResults;
};

class DdrocrInstance
{
public:
    std::string dataPath;
    DdrocrInstance(std::string dataPath);
    ~DdrocrInstance();
    // TODO use outputimg path declared in class
    ProcessImgResult process_image(cv::Mat inputImg);

private:
    // Helper methods
    OCRWrapper ocrWrapper;
    cv::Mat otsuToLogical(const cv::Mat &gray, bool invert = false) const;
    cv::Mat logicalToDisplayU8(const cv::Mat &logical) const;
    cv::Rect expandRoi(cv::Rect roi, cv::Point expand);
    std::vector<cv::Point2f> rectToPoints(const cv::Rect &r);
    cv::Rect offsetToRoi(cv::Point tl, cv::Point br, cv::Point expansion = {0, 0});
    char classifyDigit_0_or_1(const cv::Mat &input);

    OCRResult getPreprocessedRoiImage(
        const cv::Mat &warpedImg,
        const cv::Rect &ROI_Target,
        const cv::Rect &ROI_Details,
        const cv::Point &warped_details_top_left,
        const cv::Point &expand,
        const std::string &imageName,
        OCRType type);

    void save_img(const std::string &fileName, cv::Mat img);
};
