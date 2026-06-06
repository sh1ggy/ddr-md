# Plan: Integrate PP-OCRv5_mobile_det (Detection Model) via ONNX Runtime

## Goal

Add PaddleOCR's text detection model as a sibling to the existing `ocr_onnx.cpp` recognition wrapper. After this, the pipeline can be:

```
input image → detector (DB) → N quadrilateral text boxes → per-box perspective-corrected crop → recogniser → text
```

This eliminates the hardcoded ROI coordinates in `COCRConfig` for arbitrary text regions, and gives a proper learned alternative to the HSV+morphology Details-finder.

## Reuse from rec integration

ONNX Runtime (iOS xcframework + Android `.so`) is already vendored and linked. No build-system changes are needed beyond compiling one new source file. The `Ort::Env` instance in `OCRWrapper` can be shared if desired, or a separate `Env` is fine.

## Steps

### 1. Obtain the model

- **Source:** `https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det` — contains `inference.json` (PIR format, 230 kB), `inference.pdiparams` (4.69 MB), `inference.yml` (config, 903 B).
- **Alternative (skip conversion):** `https://huggingface.co/AIPLUX/paddleocr-ppocrv5-onnx` has pre-converted ONNX for both det + rec.
- **Conversion command (PIR-aware):**
  ```
  paddle2onnx --model_dir ./PP-OCRv5_mobile_det \
    --model_filename inference.json \
    --params_filename inference.pdiparams \
    --save_file ppocr_mobile_det.onnx \
    --opset_version 11 \
    --enable_onnx_checker True
  ```
  Note: filename flag is `inference.json` (PIR), not `.pdmodel` like older PaddleOCR versions.

### 2. Place assets

- `assets/models/ppocr_mobile_det.onnx` (~5 MB expected)
- No dictionary file needed — detector outputs geometry, not text.
- Add to the existing `loadModels()` copy list in `lib/ocr_processor.dart` so it's copied to writable storage at startup.

### 3. New C++ class: `DetWrapper`

New file: `native_opencv/ios/Classes/det_onnx.cpp` (and matching `det_wrapper.h`). Mirrors the structure of `ocr_onnx.cpp` / `ocr_wrapper.h`.

**Interface:**
```cpp
struct DetBox {
    cv::Point2f corners[4]; // ordered TL, TR, BR, BL
    float score;            // mean prob inside the box
};

class DetWrapper {
public:
    DetWrapper(const std::string &dataPath);
    ~DetWrapper();
    std::vector<DetBox> detect(const cv::Mat &bgrInput);
    std::string debugDir; // optional, for saving prob maps
private:
    std::unique_ptr<Ort::Env>     env;
    std::unique_ptr<Ort::Session> session;
};
```

### 4. Preprocessing (`DetResizeForTest`)

Source: `ppocr/data/imaug/operators.py::resize_image_type0`.

- Channel order: **BGR** (do NOT swap to RGB — confirmed from inference.yml)
- Resize so the longest side = **960** (`resize_long: 960` from inference.yml)
- Round both H and W to nearest multiple of 32, minimum 32:
  `resize_h = max(int(round(h_scaled / 32) * 32), 32)`
- Normalize: `(pixel / 255.0 - mean) / std` with **ImageNet** mean/std:
  `mean = [0.485, 0.456, 0.406]`, `std = [0.229, 0.224, 0.225]`
- Layout: NCHW float32, shape `[1, 3, H, W]`
- Keep the scale factors `(srcW / inputW, srcH / inputH)` to remap output boxes back to original image coordinates.

### 5. Inference

- Input name: `"x"` — but call `session->GetInputNameAllocated(0, allocator)` to be safe (paddle2onnx sometimes renames).
- Output name: typically `"sigmoid_0.tmp_0"` — same, query at runtime.
- Output shape: `[1, 1, H, W]` — single-channel probability map, sigmoid'd into `[0, 1]`.

### 6. DB postprocess (`DBPostProcess`)

Source: `ppocr/postprocess/db_postprocess.py::boxes_from_bitmap`.

**Params (from inference.yml, NOT the python class defaults):**
- `thresh = 0.3`
- `box_thresh = 0.6`
- `max_candidates = 1000`
- `unclip_ratio = 1.5`
- `min_size = 3`

**Pipeline:**
1. Binarize prob map: `mask = (prob > thresh) * 255` → uint8
2. `cv::findContours(mask, RETR_LIST, CHAIN_APPROX_SIMPLE)`
3. For each contour (cap at `max_candidates`):
   a. `cv::minAreaRect` → get 4 corner points
   b. Filter if `min(rect.width, rect.height) < min_size`
   c. Compute box score: mean of prob map values inside the axis-aligned bbox of the corners. Skip if `< box_thresh`.
   d. **Unclip** the polygon: offset distance = `area * unclip_ratio / perimeter`, apply Vatti / Minkowski polygon offset using Clipper.
   e. `cv::minAreaRect` on the unclipped polygon → final 4 corners
   f. Rescale corners from the resized input dims back to original image dims
4. Return array of `DetBox`.

### 7. Vendor Clipper

- **Drop-in choice:** Clipper2 (https://github.com/AngusJohnson/Clipper2) — single header + single source, MIT, modern API. Or original Clipper (`clipper.hpp` + `clipper.cpp`).
- Place under `native_opencv/ios/Classes/third_party/clipper2/` so both iOS pod and Android CMake pick it up (the same `../ios/Classes` paths are already shared).
- Reference implementation: PaddleOCR's own C++ deploy at `deploy/cpp_infer/src/modules/text_detection/processors.cc` — uses ClipperLib with `jtRound` / `etClosedPolygon`.

**Unclip snippet (pattern):**
```cpp
Clipper2Lib::ClipperOffset co;
co.AddPath(path, JoinType::Round, EndType::Polygon);
Paths64 solution;
co.Execute(distance, solution);
```

### 8. Helper: `getRotateCropImage` (perspective crop)

Source: `tools/infer/utility.py::get_rotate_crop_image`. Implement as free function in `det_onnx.cpp` or a util header:

1. `cropW = max(||p0-p1||, ||p2-p3||)`, `cropH = max(||p0-p3||, ||p1-p2||)`
2. `dst = [[0,0],[cropW,0],[cropW,cropH],[0,cropH]]`
3. `M = cv::getPerspectiveTransform(srcCorners, dst)`
4. `cv::warpPerspective(input, out, M, Size(cropW, cropH), INTER_CUBIC, BORDER_REPLICATE)`
5. **If `cropH / cropW >= 1.5`, rotate 90° CCW** so the text is horizontal for the recogniser.
6. Return `cv::Mat` ready to feed into `OCRWrapper::performOCR`.

### 9. Wire into `DdrocrInstance`

Add a member `DetWrapper detWrapper` alongside `OCRWrapper ocrWrapper`. Provide a new path in `process_image` (or a separate method) that:

1. Runs `detWrapper.detect(inputImg)` → vector of boxes
2. For each box → `getRotateCropImage` → `ocrWrapper.performOCR`
3. Returns the text + box list

The existing HSV+homography path can stay alongside as a fallback, or be removed once the detector proves sufficient.

### 10. Asset path plumbing

The existing `DdrocrInstance(dataPath, cfg)` already receives a writable path. `DetWrapper` constructor loads `dataPath + "/models/ppocr_mobile_det.onnx"` — same convention as `OCRWrapper`. No FFI signature changes required.

## Verification

1. **Build both platforms** — no linker changes needed; only one new `.cpp` + Clipper sources added to the same shared sources list.
2. **Smoke test:** Feed a DDR results screenshot in. Save the prob map (`prob_map.png`) and the post-unclip boxes drawn on the input. Expect at least the "Details", "Play Graph", and the various score number boxes to appear.
3. **End-to-end:** Pipe each detected box through `getRotateCropImage` + `performOCR`. The "Details" tab text should decode cleanly.
4. **Performance:** Detector at 960 long-side is ~50-200ms on mobile. Log timings to confirm it's acceptable for the per-image (not per-frame) flow.

## Common pitfalls

- **Wrong normalisation:** detector uses **ImageNet mean/std** (not `(x/255-0.5)/0.5` like the rec model). Mixing these up silently kills detection quality.
- **PIR format flag:** use `--model_filename inference.json`, not `inference.pdmodel`. PP-OCRv5 ships PIR; older guides assume the old format.
- **Hardcoded I/O names:** query `session->GetInputNameAllocated` / `GetOutputNameAllocated` — paddle2onnx may rename.
- **Skipping unclip:** `cv::approxPolyDP` is polygon simplification, not Minkowski offset. Without unclip, the boxes are too tight and cut off characters.
- **Box score from wrong region:** use mean prob over the axis-aligned bbox of the **mini-box** (pre-unclip), not the unclipped polygon — the "fast" path. Mixing the two changes the `box_thresh` calibration.
- **Forgetting rescale:** boxes are in the *resized* input coordinate system. Must divide by the resize scale before returning, otherwise they don't align with the original frame.
- **`box_thresh = 0.6` not `0.7`:** the python class default is 0.7, but `inference.yml` overrides to 0.6 for PP-OCRv5_mobile_det. Read the model's own yaml.

## Files added / modified

**Add:**
- `native_opencv/ios/Classes/det_wrapper.h`
- `native_opencv/ios/Classes/det_onnx.cpp`
- `native_opencv/ios/Classes/third_party/clipper2/clipper.h`, `clipper.cpp` (or equivalent)
- `assets/models/ppocr_mobile_det.onnx`

**Modify:**
- `native_opencv.podspec` — add new source files / third_party include path
- `native_opencv/android/CMakeLists.txt` — add new source files / Clipper to `add_library`
- `native_opencv/ios/Classes/ddrocr_instance.h/.cpp` — wire `DetWrapper` member + new detection path
- `lib/ocr_processor.dart` — add `ppocr_mobile_det.onnx` to the asset copy list
