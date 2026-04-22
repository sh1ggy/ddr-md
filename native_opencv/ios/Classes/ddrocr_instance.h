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

struct COCRConfig
{
    int border                    = 30;
    int psm_eng                   = 6;   // tesseract::PSM_SINGLE_BLOCK
    int psm_engjp                 = 8;   // tesseract::PSM_SINGLE_WORD
    int gaussian_blur_size        = 3;
    double simplification_epsilon = 0.07;
    // roi order: details, score, marvelous, perfect, great, good, miss, flare, title, username, difficulty, max_combo
    // each row: {x1, y1, x2, y2, expand_x, expand_y}  (details has no expansion so last two are 0)
    int roi[12][6] = {
        {2054,2348,2418,2450, 0, 0}, // details
        {2700,2551,2968,2611, 5, 0}, // score
        {1896,2549,2018,2599, 0, 0}, // marvelous
        {1896,2608,2018,2657, 0, 4}, // perfect
        {1896,2664,2018,2702, 0, 6}, // great
        {1896,2727,2018,2771, 0, 5}, // good
        {1896,2825,2018,2879, 0, 0}, // miss
        {1649,2466,1817,2508, 0, 7}, // flare
        {1210,2075,1744,2133, 0,10}, // title
        {2180,1388,2465,1439,10,10}, // username
        {2056,1463,2627,1536,10,10}, // difficulty
        {2665,2779,2797,2831, 0, 0}, // max_combo
    };
};

class DdrocrInstance
{
public:
    std::string dataPath;
    std::string debugDir; // timestamped output directory for current run
    DdrocrInstance(std::string dataPath);
    ~DdrocrInstance();
    // TODO use outputimg path declared in class
    ProcessImgResult process_image(cv::Mat inputImg);
    void reloadConfig();

private:
    COCRConfig config;
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
