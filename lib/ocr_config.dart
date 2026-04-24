// OCR configuration — edit values here and flutter build to apply.
// No C++ recompilation needed.
//
// ocrRoi entries: ([x1, y1, x2, y2], (expand_x, expand_y))
// Coordinates are in 4000×5000 warped image space.

const int roiX1 = 0;
const int roiY1 = 1;
const int roiX2 = 2;
const int roiY2 = 3;
const int roiExpandX = 4;
const int roiExpandY = 5;

const double ocrAreaMinFactor = 0.00082; // 0.082% of image area
const double ocrAreaMaxFactor = 0.0082;  // 0.82% of image area

const int ocrBorder = 30;
const int ocrPsmEng = 6; // PSM_SINGLE_BLOCK
const int ocrPsmEngJP = 8; // PSM_SINGLE_WORD
const int ocrGaussianBlurSize = 3; // must be odd
const double ocrSimplificationEpsilon = 0.07;

const List<(List<int>, (int, int))> ocrRoi = [
  ([2054, 2348, 2418, 2450], (0,  0)), // details
  ([2700, 2551, 2968, 2611], (5,  0)), // score
  ([1896, 2549, 2018, 2599], (0,  0)), // marvelous
  ([1896, 2608, 2018, 2657], (0,  4)), // perfect
  ([1896, 2664, 2018, 2702], (0,  6)), // great
  ([1896, 2727, 2018, 2771], (0,  5)), // good
  ([1896, 2825, 2018, 2879], (0,  0)), // miss
  ([1649, 2466, 1817, 2508], (0,  7)), // flare
  ([1210, 2075, 1744, 2133], (0, 10)), // title
  ([2180, 1388, 2465, 1439], (10, 10)), // username
  ([2056, 1463, 2627, 1536], (10, 10)), // difficulty
  ([2665, 2779, 2797, 2831], (0,  0)), // max_combo
];
