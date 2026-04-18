## Plan: Fix Tesseract OCR Preprocessing Pipeline

The current per-ROI preprocessing (`crop → top-hat → gray → Otsu → complement → OCR`) is missing several critical steps recommended by Tesseract docs and the MATLAB OCR guide: no upscaling (ROIs are tiny ~122×50 px), no DPI hint (defaults to 70), no border padding, and no denoising blur. Changes are scoped to `performOCR` in `ocr_android.cpp` and `getPreprocessedRoiImage` in `ddrocr_instance.cpp`.

### Steps

1. **Upscale ROI 3× before binarization** in `getPreprocessedRoiImage` (ddrocr_instance.cpp ~L470): after cropping and before the top-hat step, apply `cv::resize` with `INTER_CUBIC` at 3× scale. This brings ~50 px-high digit ROIs to ~150 px — comfortably above Tesseract's minimum x-height threshold. Rescale the top-hat kernel proportionally (31×31 → ~93×93) so it still targets the same relative illumination artifacts.

2. **Apply light GaussianBlur after grayscale, before Otsu** in `getPreprocessedRoiImage` (ddrocr_instance.cpp ~L478-L480): add `cv::GaussianBlur(gray, gray, cv::Size(3,3), 0)` between the `cvtColor` to gray and the `otsuToLogical` call. A 3×3 kernel denoises without merging adjacent glyphs at 3× scale.

3. **Add white border padding after binarization** in `getPreprocessedRoiImage` (ddrocr_instance.cpp ~L484-L485): after the complement step produces `BW2` (dark text on light background), call `cv::copyMakeBorder(BW2, BW2, 10, 10, 10, 10, cv::BORDER_CONSTANT, cv::Scalar(0))` — padding with 0 (background) in the logical image, so Tesseract sees whitespace around the text region.

4. **Set DPI to 300 on the Tesseract API** in `performOCR` (ocr_android.cpp ~L155-L170): after `api->SetPageSegMode(...)` and before `api->SetImage(pixImage)`, call `api->SetVariable("user_defined_dpi", "300")` for all OCR types. This tells Tesseract's internal scaling heuristics to treat the input as 300 DPI, matching its training data.

5. **Remove redundant re-binarization in `performOCR`** (ocr_android.cpp ~L107-L131): the input from `getPreprocessedRoiImage` is already a clean logical 0/1 image (dark text on light background). The current `performOCR` re-applies Otsu thresholding and min/max checks on an already-binarized image. Simplify to: assert single-channel CV_8U, skip the redundant threshold block, and directly build the `Pix` from the input logical mat. This avoids double-binarization artifacts.

6. **Verify dark-on-light orientation is consistent** across both files: the MATLAB guide mandates dark text on light background. In `getPreprocessedRoiImage`, `BW2` is the complement of `BW1` (Otsu), making text=1, background=0 in logical space. In `performOCR`, Pix bit 1 = black, 0 = white (Leptonica convention). Confirm that `SET_DATA_BIT` for `matRow[col] != 0` correctly maps text pixels to black ink — this is already correct and should be preserved.

### Other Considerations
- Save images as PNG and also save them in the ocr_android file just before they are sent off to tesseract 
