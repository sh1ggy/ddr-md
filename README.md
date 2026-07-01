# DDR MD

![sh1ggy](https://img.shields.io/badge/sh1ggy-darkblue?style=plastic) ![Year](https://img.shields.io/badge/Year-2024-red?style=plastic) ![Language](https://img.shields.io/badge/dart-grey?style=plastic&logo=dart) ![Framework](https://img.shields.io/badge/Flutter-grey?style=plastic&logo=flutter) 

This is the repo for the mobile application for DDR MD (name pending), a self-improvement platform made solely for DDR & ITG players.

## About
This project is being made to assist with the self-improvement process involved in the pad-stomping games of DDR and ITG before, during and after play. The approach with this project is to not only display chart information in a digestible format to make chart study easier, but also provide tools for you to take personal notes and reflect upon the quirks of your specific playstyle.  

## Usage
The intended usage of this application is to use it while you're playing DDR. For more information about release-specific usage, refer to [this user guide](./wiki/Release%201.md)

## Stack
- [Flutter](https://flutter.dev/), our chosen mobile development framework. 

## Development
- Set up your Flutter environment as per [Flutter's getting started guide](https://docs.flutter.dev/get-started/install)
- Install the appropriate Flutter [Visual Studio Code extension](https://docs.flutter.dev/tools/vs-code)
- Install the appropriate dependencies with `flutter pub get`
- Either run the project via the debugger or with `flutter run`

### OCR Pipeline

OCR is implemented in native C++ on top of OpenCV and the ONNX Runtime, calling PaddleOCR's PP-OCRv6 models for text detection and recognition. The score panel runs detection + recognition over a single combined ROI; other fields (title, username, difficulty, details) run recognition only over hand-picked crops. If detection fails, the pipeline falls back to recognition over hardcoded ROIs. The migration from the previous Tesseract engine and the v5→v6 model swap are documented in the plan docs under [docs/](./docs/) ([plan-paddle-det-integration.md](./docs/plan-paddle-det-integration.md), [plan-paddle-v6-migration.md](./docs/plan-paddle-v6-migration.md)).

#### ONNX Runtime

The native module links against the prebuilt **ONNX Runtime iOS xcframework**, vendored at `native_opencv/ios/libs/onnxruntime.xcframework` and referenced as a `vendored_framework` in `native_opencv/ios/native_opencv.podspec`. ORT sessions are created once at startup in [native_opencv/ios/Classes/ocr_onnx.cpp](./native_opencv/ios/Classes/ocr_onnx.cpp) — one for detection (`detSession`, optional) and one for recognition (`session`).

#### Det & Rec Models

All models live under `assets/models/`, are bundled via the `assets/models/` directory entry in `pubspec.yaml`, and copied to the app data dir at startup by the copy list in [lib/ocr_processor.dart](./lib/ocr_processor.dart). Each tier is a `det` + `rec` + `dict` triplet:

| Tier | Rec | Det | Dict |
|---|---|---|---|
| tiny | `ppocr_tiny_rec.onnx` | `ppocr_tiny_det.onnx` | `ppocrv6_dict.txt` |
| **small (default)** | `ppocr_small_rec.onnx` | `ppocr_small_det.onnx` | `ppocrv6_small_dict.txt` |
| medium | `ppocr_medium_rec.onnx` | `ppocr_medium_det.onnx` | `ppocrv6_medium_dict.txt` |
| mobile (v5, legacy) | `ppocr_mobile_rec.onnx` | `ppocr_mobile_det.onnx` | `ppocrv5_dict.txt` |

The active triplet is selected in native code — the default is **small v6**, set at [ocr_onnx.cpp:95-97](./native_opencv/ios/Classes/ocr_onnx.cpp#L95-L97). A `ModelSet` override lets the offline `model_compare` harness swap tiers without rebuilding the app. The recogniser is required; the detector is loaded inside a try/catch and the pipeline degrades to recogniser-only (hardcoded ROIs) if it's missing.

The PP-OCRv6 tiny/small/medium variants ship pre-converted to ONNX on Hugging Face, so no `paddle2onnx` step is needed — download the `.onnx` and dict from the corresponding [PaddlePaddle](https://huggingface.co/PaddlePaddle) repo and drop them into `assets/models/`. (The legacy v5 mobile models were produced with `paddle2onnx`; see [docs/plan-paddle-v6-migration.md](./docs/plan-paddle-v6-migration.md) for that history.)

#### Android Build Steps

**Prerequisites:** Android SDK + NDK (CMake 3.18+), Java 17 (for Gradle), `wget` + `unzip`.

1. `bash scripts/init.sh` — downloads and stages the native dependencies:
   - **OpenCV 4.12 Android SDK** → `libopencv_java4.so` into `native_opencv/android/src/main/jniLibs/<ABI>/` for all four ABIs (`armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`); OpenCV C++ headers into `native_opencv/android/src/main/jniLibs/include/`.
   - **ONNX Runtime Android AAR** (`com.microsoft.onnxruntime:onnxruntime-android`, pinned in the script) → `libonnxruntime.so` into the same per-ABI `jniLibs/` folders; ORT C/C++ headers into `native_opencv/android/src/main/cpp/onnxruntime/include/`.
2. `flutter build apk` (or `flutter run`) — Gradle invokes CMake ([native_opencv/android/CMakeLists.txt](./native_opencv/android/CMakeLists.txt)) to build the `native_opencv` shared library, which links against the per-ABI `.so` files in `jniLibs/` as `IMPORTED` targets.

**`jniLibs/` layout** — Gradle auto-packages anything under `src/main/jniLibs/<ABI>/` into the APK at `lib/<ABI>/`, where the dynamic linker finds it at runtime:

```
native_opencv/android/src/main/jniLibs/
├── armeabi-v7a/
│   ├── libopencv_java4.so
│   └── libonnxruntime.so
├── arm64-v8a/
│   ├── libopencv_java4.so
│   └── libonnxruntime.so
├── x86/
│   └── ...
└── x86_64/
    └── ...
```

The whole `jniLibs/` directory is gitignored — everything in it is produced by `scripts/init.sh`, so re-run the script after a clean checkout or when bumping `OPENCV_VERSION` / `ORT_VERSION` at the top of the script.

#### iOS Build Steps

**Prerequisites:** Xcode with iOS SDK, CocoaPods.

1. `cd ios && pod install` — picks up `opencv2.framework` and `onnxruntime.xcframework` via the podspec.
2. `flutter build ios` (or run from Xcode/VS Code).

iOS deployment target is **13.0**.

#### OCR Tooling

A set of offline tools under [native_opencv/tools/](./native_opencv/tools/) supports tuning the OCR pipeline — picking ROIs, comparing model tiers for accuracy, and profiling per-model timing. They chain together: **pick ROIs → run the compare harness → (optionally) hand-label ground truth → view results/perf**.

| Tool | Type | Purpose |
|---|---|---|
| [roi_picker.html](./native_opencv/tools/roi_picker.html) | browser | Draw rectangles on a screenshot to pick field ROIs / template crops; copies them out or saves PNGs. |
| [model_compare](./native_opencv/tools/model_compare/main.cpp) | C++ CLI | Runs the **real** pipeline over a folder of test screenshots, once per model tier, and writes a per-field CSV + annotated crops. |
| [model_compare/index.html](./native_opencv/tools/model_compare/index.html) | browser | Ground-truth classifier — hand-label each image's fields, export `classified.csv` (autosaves to the browser). |
| [results_viewer.html](./native_opencv/tools/model_compare/results_viewer.html) | browser | Loads `results.csv` (+ optional `classified.csv`) to show per-field disagreements across models and, with ground truth, per-model accuracy. |
| [perf_viewer.html](./native_opencv/tools/model_compare/perf_viewer.html) | browser | Loads `results.csv` to show per-model timing (ms) over the warped runs. |

**roi_picker.html** — open the file in a browser, drop a result screenshot in, drag boxes over each field. `Copy ROIs` puts the coordinates on your clipboard (to paste into `ocrRoi` in [lib/ocr_config.dart](./lib/ocr_config.dart) and the mirrored `makeReferenceConfig()` in [model_compare/main.cpp](./native_opencv/tools/model_compare/main.cpp)); `Save all PNGs` exports each crop for use as a matching template.

**model_compare** — a standalone desktop build that links the real pipeline sources ([ddrocr_instance.cpp](./native_opencv/ios/Classes/ddrocr_instance.cpp), [ocr_onnx.cpp](./native_opencv/ios/Classes/ocr_onnx.cpp), [details_detector.cpp](./native_opencv/ios/Classes/details_detector.cpp)) against Homebrew OpenCV + ONNX Runtime.

```bash
brew install opencv onnxruntime
cd native_opencv/tools/model_compare
cmake -B build && cmake --build build
./build/model_compare               # uses ../assets and ./tests by default
# overrides: --assets <dir> --tests <dir> --out <results.csv> --images-out <dir>
```

It sweeps all four model tiers (`mobile_v5`, `small_v6`, `tiny_v6`, `medium_v6` — see [main.cpp:178-183](./native_opencv/tools/model_compare/main.cpp#L178-L183)) over every `.jpg`/`.jpeg` in the tests dir and writes `results.csv` plus annotated crops under `results_images/`. It's built with `NDEBUG` so the pipeline's `save_img()` doesn't spray debug PNGs into `assets/`.

> ⚠️ The ROIs in `makeReferenceConfig()` ([main.cpp:54-78](./native_opencv/tools/model_compare/main.cpp#L54-L78)) mirror `ocrRoi` in [lib/ocr_config.dart](./lib/ocr_config.dart). Keep the two in sync when you re-pick ROIs.

**Reviewing results** — open `results_viewer.html`, load the generated `results.csv`. In results-only mode it highlights fields where the models disagree. To get pass/fail accuracy, first label ground truth in `index.html` (export `classified.csv`), then load that alongside — the viewer expects columns `image,field,truth`. `perf_viewer.html` reads the same `results.csv` for timing.

## Credits
- This project takes heavy inspiration from the existing [DDR BPM](https://ddrbpm.com/) application, with the data sourced from the process spun up by [xiexingwu](https://github.com/xiexingwu) 
- Credits to the Brisbane DDR community for helping with feedback during development.

### Collaborators

| [<img src="https://github.com/ariit0.png" width="60px;"/><br /><sub>Ariit0</sub>](https://github.com/ariit0) | [<img src="https://github.com/propablo.png" width="60px;"/><br /><sub>ProPablo</sub>](https://github.com/propablo) |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
