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

const double ocrAreaMinFactor = 0.00102; // 0.082% of image area
const double ocrAreaMaxFactor = 0.00702; // 0.82% of image area

const int ocrBorder = 20;
const int ocrPsmEng = 8; // PSM_SINGLE_WORD
const int ocrPsmEngJP = 8; // PSM_SINGLE_WORD
const int ocrGaussianBlurSize = 3; // must be odd
const double ocrSimplificationEpsilon = 0.07;
const double ocrResolutionScale = 3.0; // upscale factor applied to each ROI before binarization
const int ocrTophatKernelSize = 41; // morphological top-hat kernel size (must be odd); sized for original ROI resolution (top-hat now runs before upscale)
const int ocrMorphWidth = 360;  // HSV blob morphology opening kernel width
const int ocrMorphHeight = 90;  // HSV blob morphology opening kernel height

// New
const List<(List<int>, (int, int))> ocrRoi = [
  ([2122, 2344, 2448, 2435], (0, 0)), // details
  ([2710, 2527, 2933, 2578], (5, 6)), // score
  ([1986, 2528, 2089, 2576], (0, 0)), // marvelous
  ([1986, 2576, 2089, 2625], (0, 0)), // perfect
  ([1986, 2625, 2089, 2680], (0, 0)), // great
  ([1986, 2680, 2089, 2726], (0, 0)), // good
  ([1986, 2780, 2089, 2827], (0, 2)), // miss
  ([1768, 2454, 1768, 2454], (0, 0)), // flare
  ([1353, 2106, 1849, 2152], (0, 0)), // title
  ([2215, 1486, 2494, 1535], (0, 0)), // username
  ([2128, 1559, 2569, 1619], (0, 0)), // difficulty
  ([2690, 2729, 2797, 2771], (0,   0)), // max_combo
];



