# Plan: Unify iOS/Android OCR on Tesseract

## TL;DR
Replace the iOS Vision-based OCR backend with the same Tesseract+Leptonica pipeline Android uses, so both platforms share a single OCR implementation. Keep the Vision/.mm code stubbed (not deleted) for potential future use. The main challenge is getting Tesseract+Leptonica compiled for iOS arm64 via the podspec.

---

## Phase 1: Build System — Tesseract+Leptonica for iOS

**Goal:** Get Tesseract and Leptonica (plus libjpeg/libpng) compiling as static libraries for iOS arm64.

### Step 1.1: Add Tesseract/Leptonica sources to the iOS build
The sources already exist at `native_opencv/android/src/main/cpp/{tesseract,leptonica,libjpeg,libpng}`. The iOS podspec currently can't use CMake subdirectories directly — CocoaPods compiles `.c`/`.cpp` files listed via `s.source_files`.

**Approach options:**
- **Option A (Recommended): Prebuilt static frameworks.** Build Tesseract+Leptonica+deps as `.xcframework` bundles offline (via a build script) and vendor them in the podspec, similar to how `opencv2.framework` is already handled. This avoids the complexity of compiling 100+ C files through CocoaPods.
- **Option B: Compile from source via podspec subspecs.** Add all Tesseract/Leptonica/libjpeg/libpng `.c`/`.cpp` source files to the podspec. Requires careful header search paths, preprocessor defines, and will significantly slow down builds.

### Step 1.2: Create iOS build script (if Option A)
- File: `scripts/build_tesseract_ios.sh`
- Compile libjpeg, libpng, leptonica, tesseract from the existing sources under `native_opencv/android/src/main/cpp/` for iOS arm64
- Use the same CMakeLists.txt files with an iOS CMake toolchain (`-DCMAKE_SYSTEM_NAME=iOS`)
- Output: static `.a` libraries or `.xcframework` bundles placed into `native_opencv/ios/`
- Add the output path to `.gitignore` (like `opencv2.framework` already is)

### Step 1.3: Update `native_opencv/ios/native_opencv.podspec`
- Add vendored static libraries/frameworks for tesseract, leptonica, libjpeg, libpng
- Add `HEADER_SEARCH_PATHS` for tesseract (`include/tesseract/`) and leptonica headers
- Keep `Vision` framework listed (stubbed code still imports it) but it becomes optional
- Add preprocessor define for leptonica config (e.g., `HAVE_LIBJPEG`, `HAVE_LIBPNG`, `HAVE_LIBZ`)

---

## Phase 2: C++ Layer — Unify OCR Implementation

### Step 2.1: Update `native_opencv/ios/Classes/ocr_wrapper.h`
- Change the `#if defined(__ANDROID__)` guard around `tesseract::TessBaseAPI *api` and `#include <tesseract/baseapi.h>` to include iOS:
  ```
  #if defined(__ANDROID__) || defined(__APPLE__)
  ```
  Or simply remove the guard entirely since both platforms now use Tesseract.

### Step 2.2: Stub `native_opencv/ios/Classes/ocr_ios.mm`
- Wrap the entire Vision implementation behind a new guard (e.g., `#if USE_VISION_OCR`) so it compiles but is inactive by default
- Or: rename to `ocr_ios_vision.mm.bak` and exclude from compilation
- **Preferred approach:** Keep the file, add `#if 0` / `#endif` around the `OCRWrapper` constructor, destructor, and `performOCR` body to prevent duplicate symbol errors with the Tesseract version. Add a comment explaining it's preserved for future use.
- Alternative: factor the Vision code into a separate class (`VisionOCRWrapper`) so it doesn't collide with the Tesseract `OCRWrapper`.

### Step 2.3: Enable `ocr_android.cpp` for iOS
- Remove the outer `#ifdef __ANDROID__` / `#endif` guard that wraps the entire file
- Fix the leptonica include for iOS: the `#ifdef __ANDROID__` / `#else` around `<allheaders.h>` vs `<leptonica/allheaders.h>` needs updating based on actual iOS header search paths
- This file provides `OCRWrapper::OCRWrapper()`, `~OCRWrapper()`, and `performOCR()` — the exact Tesseract pipeline to reuse
- Rename file to `ocr_tesseract.cpp` (optional, for clarity since it's no longer Android-only)

### Step 2.4: Update `native_opencv/ios/Classes/ddrocr_instance.cpp`
Two platform-specific branches need unification:

**Lines ~230-236 (Details-detection ROI):**
- Remove the `#ifdef __APPLE__` branch that converts to display U8
- Use the Android (else) branch for both platforms: `cv::Mat roiMat = preprocessed_BW3(details_roi);`

**Lines ~518-535 (getPreprocessedRoiImage):**
- Remove the `#if defined(__APPLE__)` branch (Otsu 0-255 + `Scalar(255)` border)
- Use the Android branch for both platforms: `otsuToLogical()` → `subtract` → `copyMakeBorder` with `Scalar(1)`

### Step 2.5: Remove `#ifdef __IOS__` confidence skip (line ~248)
- The `#ifdef __IOS__` block that skips low-confidence Vision results can be removed or re-evaluated, since Tesseract confidence behaves differently

---

## Phase 3: Dart Layer — Enable Tessdata on iOS

### Step 3.1: Update `lib/ocr_processor.dart` `loadTessdata()`
- Remove the `if (!Platform.isAndroid) return;` guard
- Change to: `if (!Platform.isAndroid && !Platform.isIOS) return;` (or just remove the early return entirely)
- The rest of the method (copy `eng.best.traineddata` to `appDir/tessdata/`) already works cross-platform since it uses `path_provider`

---

## Phase 4: Cleanup & Verification

### Step 4.1: Update Android CMakeLists.txt (if file renamed)
- If `ocr_android.cpp` is renamed to `ocr_tesseract.cpp`, update the source file reference in `native_opencv/android/CMakeLists.txt` line 20

### Step 4.2: Ensure `process_camera_image` still works
- The `#ifdef __ANDROID__` / `#else` in `native_opencv.cpp` lines ~188-201 for YUV vs RGBA conversion is **correct and should stay** — camera frame formats genuinely differ per platform

---

## Relevant Files

- `native_opencv/ios/Classes/ocr_wrapper.h` — Remove Tesseract `#ifdef __ANDROID__` guard
- `native_opencv/ios/Classes/ocr_ios.mm` — Stub the Vision implementation (preserve but disable)
- `native_opencv/ios/Classes/ocr_android.cpp` — Remove `#ifdef __ANDROID__` wrapper, make cross-platform
- `native_opencv/ios/Classes/ddrocr_instance.cpp` — Remove `#ifdef __APPLE__` branches at lines ~230 and ~518, use Android (Tesseract) path for both
- `native_opencv/ios/native_opencv.podspec` — Add Tesseract/Leptonica deps, keep Vision framework
- `lib/ocr_processor.dart` — Remove platform guard in `loadTessdata()`
- `native_opencv/android/CMakeLists.txt` — Update if sources renamed
- `scripts/build_tesseract_ios.sh` — New: build script for iOS Tesseract static libs

## Verification

1. **Build script test:** Run `scripts/build_tesseract_ios.sh` and confirm it produces arm64 static libs for tesseract, leptonica, libjpeg, libpng
2. **Pod install:** Run `cd ios && pod install` and verify it links without errors
3. **iOS compile:** `flutter build ios --no-codesign` succeeds without duplicate symbols or missing headers
4. **Android compile:** `flutter build apk` still succeeds (no regressions)
5. **Runtime test (iOS):** Load the app on iOS device, verify `loadTessdata()` copies `eng.best.traineddata` to documents dir
6. **OCR test (iOS):** Run OCR on a DDR results screen image and verify Tesseract produces digit/text results (compare with Android output for same image)
7. **Camera test (iOS):** Live camera feed still detects the Details ROI and produces OCR output

## Decisions

- Vision `.mm` code is **stubbed, not deleted** — preserved behind `#if 0` or refactored into a separate class
- Camera frame format conversion (`native_opencv.cpp`) stays platform-specific (YUV vs RGBA) — this is correct
- Using prebuilt static libs (Option A) is recommended over compiling from source in podspec
- The `#ifdef __IOS__` confidence threshold skip at line ~248 of `ddrocr_instance.cpp` should be removed since it was Vision-specific

## Further Considerations

1. **Build approach for Tesseract iOS libs:** Option A (prebuilt static `.a`/`.xcframework` via offline script, vendored like opencv2.framework) is recommended over Option B (compiling 100+ source files through CocoaPods). The existing CMakeLists.txt can be reused with iOS CMake toolchain. Does this work for you?
2. **Simulator support:** The current podspec excludes `i386 arm64` for simulator. Tesseract iOS libs would need to be built for both `arm64-iphoneos` and `arm64-iphonesimulator` if you want simulator testing — or just device-only for now?
3. **ocr_android.cpp rename:** Optionally rename to `ocr_tesseract.cpp` for clarity since it's no longer Android-only. Minor cosmetic change but improves readability.
