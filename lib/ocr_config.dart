// OCR configuration — edit values here and flutter build to apply.
// No C++ recompilation needed.
//
// ocrRoi entries: ([x1, y1, x2, y2], (expand_x, expand_y))
// Coordinates are in 4000×5000 warped image space (feature/opencv ROIs).

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

// Minimum normalised correlation (TM_CCOEFF_NORMED) for a candidate HSV blob
// to be accepted as the "Details" badge by DetailsDetector. Range 0..1.
// Lower = more permissive (risk false positives), higher = stricter (risk
// missing the real badge in poor lighting).
const double ocrDetailsTemplateMinScore = 0.4;

// ---------------------------------------------------------------------------
// ROI sets. Two candidate ROI layouts are kept side by side so they can be
// A/B tested (see native_opencv/tools/model_compare). Each layout has a paired
// combined ROI — they MUST switch together. To change the active layout, flip
// the two `ocrRoi` / `ocrCombinedRoi` aliases at the bottom of this block to
// point at the same suffix (…Reference or …Imperfect).
//
// Combined ROI covers all per-field regions — fed to the PaddleOCR detection
// model. Detection finds text boxes inside it; each per-field rectangle is then
// used purely as a spatial anchor to label which detection corresponds to which
// field (score, marvelous, title, etc.).
//
// Per-field roi order is fixed — indices must match ROI_IDX_* in
// ddrocr_instance.cpp.
// ---------------------------------------------------------------------------

// Reference layout — native 2554×1442 source-image space.
const List<int> ocrCombinedRoiReference = [1299, 860, 2296, 1239];
const List<(List<int>, (int, int))> ocrRoiReference = [
  ([1669, 864, 1920, 936], (0, 0)), // details
  ([2129, 1005, 2273, 1042], (5, 6)), // score
  ([1540, 1013, 1642, 1050], (0, 0)), // marvelous
  ([1540, 1049, 1642, 1086], (0, 0)), // perfect
  ([1540, 1085, 1642, 1122], (0, 0)), // great
  ([1540, 1121, 1642, 1158], (0, 0)), // good
  ([1540, 1193, 1642, 1230], (0, 2)), // miss
  ([1385, 954, 1507, 984], (0, 0)), // flare
  ([1051, 669, 1506, 719], (0, 0)), // title
  ([1752, 181, 1952, 220], (0, 0)), // username
  ([1766, 233, 2026, 300], (0, 0)), // difficulty
  ([2098, 1154, 2279, 1202], (0, 0)), // max_combo
];
// Extra rects from the source table not wired into ocrRoiReference above (no
// slot in the fixed ROI_IDX_* enum). Kept for reference:
//   ok                      ([1540, 1157, 1642, 1194], (0, 0))
//   username_detection_box  ([1616, 160, 2093, 313], (0, 0))
//   mode                    ([1686, 244, 1794, 292], (0, 0))

// Imperfect layout — 4000×5000 warped space (the previous feature/opencv ROIs).
const List<int> ocrCombinedRoiImperfect = [1641, 2339, 2936, 2818];
const List<(List<int>, (int, int))> ocrRoiImperfect = [
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
  ([2690, 2729, 2797, 2771], (0, 0)), // max_combo
];

// Active selection — flip both to the same suffix to switch layouts.
const List<(List<int>, (int, int))> ocrRoi = ocrRoiReference;
const List<int> ocrCombinedRoi = ocrCombinedRoiReference;



