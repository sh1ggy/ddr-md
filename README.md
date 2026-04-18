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

### iOS Build Process

The iOS build uses the same Tesseract+Leptonica OCR pipeline as Android. The native C++ sources live in `native_opencv/android/src/main/cpp/` (shared between both platforms) and are cross-compiled into static libraries for iOS.

**Prerequisites:** Xcode with iOS SDK, CMake (`brew install cmake`), CocoaPods.

**Steps:**

1. **Init submodules** — `git submodule update --init --recursive` (pulls `Tesseract4Android` which contains the Tesseract & Leptonica source).

2. **Build static libs** — `bash scripts/build_tesseract_ios.sh`
   - Uses CMake (`scripts/ios_tesseract_cmake/CMakeLists.txt`) to cross-compile for iOS arm64 (deployment target 13.0).
   - Produces 2 static libraries in `native_opencv/ios/libs/`: `libtesseract.a`, `libleptonica.a`. (libjpeg and libpng are built during compilation but **not** vendored — `opencv2.framework` already bundles both, and linking duplicates causes symbol collisions that break `imread`.)
   - Copies public headers to `native_opencv/ios/libs/include/` (including CMake-generated `config_auto.h`).
   - The `libs/` directory is gitignored — you must run this script before building.

3. **Pod install** — `cd ios && pod install`
   - The podspec (`native_opencv/ios/native_opencv.podspec`) references the static libs as `vendored_libraries` and sets up header search paths + preprocessor defines (`OS_IOS`, `HAVE_LIBJPEG`, `HAVE_LIBPNG`, etc.).

4. **Flutter build** — `flutter build ios` or run from Xcode/VS Code.

**Key details:**
- iOS deployment target is **13.0** (required for `std::filesystem` used by Tesseract).
- The Vision OCR backend in `ocr_ios.mm` is stubbed out (`#if 0`) — both platforms now use the Tesseract backend via `ocr_android.cpp`.
- Tessdata files (`eng.best.traineddata`, `jpn.best.traineddata`) are bundled as Flutter assets and copied to the app's documents directory at runtime by `loadTessdata()` in `lib/ocr_processor.dart`.
- `scripts/init.sh` runs the full setup including the iOS build step.

## Credits
- This project takes heavy inspiration from the existing [DDR BPM](https://ddrbpm.com/) application, with the data sourced from the process spun up by [xiexingwu](https://github.com/xiexingwu) 
- Credits to the Brisbane DDR community for helping with feedback during development.

### Collaborators

| [<img src="https://github.com/ariit0.png" width="60px;"/><br /><sub>Ariit0</sub>](https://github.com/ariit0) | [<img src="https://github.com/propablo.png" width="60px;"/><br /><sub>ProPablo</sub>](https://github.com/propablo) |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
