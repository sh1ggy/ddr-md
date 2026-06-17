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

OCR is implemented in native C++ on top of OpenCV and the ONNX Runtime, calling PaddleOCR's PP-OCRv5 mobile models for text detection and recognition. The score panel runs detection + recognition over a single combined ROI; other fields (title, username, difficulty, details) run recognition only over hand-picked crops. See [docs/paddleocr-migration.md](./docs/paddleocr-migration.md) for the architectural rationale and pipeline diagram.

#### ONNX Runtime

The native module links against the prebuilt **ONNX Runtime iOS xcframework**, vendored at `native_opencv/ios/libs/onnxruntime.xcframework` and referenced as a `vendored_framework` in `native_opencv/ios/native_opencv.podspec`. ORT sessions are created once at startup in [native_opencv/ios/Classes/ocr_onnx.cpp](./native_opencv/ios/Classes/ocr_onnx.cpp) — one for detection (`detSession`, optional) and one for recognition (`recSession`).

#### Det & Rec Models

Both models live under `assets/models/` and are bundled via `pubspec.yaml`:

| File | Role | Source |
|---|---|---|
| `ppocr_mobile_det.onnx` | DBNet text detector | [PaddlePaddle/PP-OCRv5_mobile_det](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det) |
| `ppocr_mobile_rec.onnx` | CTC text recogniser | [PaddlePaddle/PP-OCRv5_mobile_rec](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec) |
| `ppocrv5_dict.txt` | Recogniser character dictionary | PP-OCRv5 release |

They are produced by converting the upstream Paddle inference exports to ONNX with `paddle2onnx`. PP-OCRv5 ships in PIR format, so the model filename is `inference.json` (not the older `inference.pdmodel`):

```bash
paddle2onnx --model_dir ./PP-OCRv5_mobile_det \
  --model_filename inference.json \
  --params_filename inference.pdiparams \
  --save_file ppocr_mobile_det.onnx \
  --opset_version 11 \
  --enable_onnx_checker True

# same invocation for PP-OCRv5_mobile_rec
```

Drop the resulting `.onnx` files into `assets/models/`. The recogniser is required; the detector is loaded inside a try/catch and the pipeline degrades to recogniser-only if it's missing.

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

## Credits
- This project takes heavy inspiration from the existing [DDR BPM](https://ddrbpm.com/) application, with the data sourced from the process spun up by [xiexingwu](https://github.com/xiexingwu) 
- Credits to the Brisbane DDR community for helping with feedback during development.

### Collaborators

| [<img src="https://github.com/ariit0.png" width="60px;"/><br /><sub>Ariit0</sub>](https://github.com/ariit0) | [<img src="https://github.com/propablo.png" width="60px;"/><br /><sub>ProPablo</sub>](https://github.com/propablo) |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
