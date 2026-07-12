# native_opencv

Flutter plugin holding the native C++ OCR pipeline for DDR MD: OpenCV image
processing plus PaddleOCR (PP-OCRv6) text detection and recognition running on
the ONNX Runtime, exposed to Dart over FFI.

## Layout

- `ios/Classes/` — the C++/Obj-C++ sources (shared by iOS **and** Android via
  the Android CMake build). Key files:
  - `ocr_onnx.cpp` / `ocr_wrapper.h` — ORT det + rec sessions, CTC decode, model selection.
  - `details_detector.*` — template-based details detection.
  - `camera_ocr_session.*`, `CameraOcrSession.mm` — live camera OCR session.
  - `native_opencv.cpp`, `jni_bridge.cpp` — FFI / JNI entry points.
- `android/CMakeLists.txt` — Android NDK build; links OpenCV + ONNX Runtime `.so`s from `jniLibs/`.
- `ios/native_opencv.podspec` — iOS pod; vendors `opencv2.framework` and `onnxruntime.xcframework`.
- `tools/model_compare/` — offline C++ harness + HTML viewers for comparing model tiers.
- `tools/roi_picker.html` — ROI picker for the recognition-only fields.

## Building

Native dependencies (OpenCV + ONNX Runtime) are staged by `scripts/init.sh` at
the repo root. See the top-level [README](../README.md#ocr-pipeline) for the
full Android/iOS build steps and the model lineup.
