#!/usr/bin/env bash
set -euo pipefail

OPENCV_VERSION="4.12.0"
ORT_VERSION="1.20.0"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_DIR="$REPO_ROOT/native_opencv"
ANDROID_JNI="$NATIVE_DIR/android/src/main/jniLibs"
ANDROID_ORT_INC="$NATIVE_DIR/android/src/main/cpp/onnxruntime/include"

mkdir -p "$REPO_ROOT/scripts/download"
cd "$REPO_ROOT/scripts/download"

# ----- OpenCV (Android SDK + iOS framework) -----
[ -f "opencv-${OPENCV_VERSION}-android-sdk.zip" ] || \
  wget -O "opencv-${OPENCV_VERSION}-android-sdk.zip" \
    "https://github.com/opencv/opencv/releases/download/${OPENCV_VERSION}/opencv-${OPENCV_VERSION}-android-sdk.zip"
[ -f "opencv-${OPENCV_VERSION}-ios-framework.zip" ] || \
  wget -O "opencv-${OPENCV_VERSION}-ios-framework.zip" \
    "https://github.com/opencv/opencv/releases/download/${OPENCV_VERSION}/opencv-${OPENCV_VERSION}-ios-framework.zip"

unzip -o "opencv-${OPENCV_VERSION}-android-sdk.zip"
unzip -o "opencv-${OPENCV_VERSION}-ios-framework.zip"

cp -r opencv2.framework "$NATIVE_DIR/ios/"
cp -r OpenCV-android-sdk/sdk/native/jni/include "$NATIVE_DIR/"

mkdir -p "$ANDROID_JNI"
cp -r OpenCV-android-sdk/sdk/native/libs/* "$ANDROID_JNI/"
cp -r OpenCV-android-sdk/sdk/native/jni/include "$ANDROID_JNI/"

# ----- ONNX Runtime Android (AAR from Maven Central) -----
# The AAR bundles per-ABI libonnxruntime.so under jni/<ABI>/ and C/C++ headers
# under headers/. Extracted with `unzip` since AARs are just zip files.
ORT_AAR="onnxruntime-android-${ORT_VERSION}.aar"
ORT_URL="https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${ORT_VERSION}/${ORT_AAR}"
ORT_EXTRACT="onnxruntime-android-${ORT_VERSION}"

[ -f "$ORT_AAR" ] || wget -O "$ORT_AAR" "$ORT_URL"
rm -rf "$ORT_EXTRACT"
mkdir -p "$ORT_EXTRACT"
unzip -o "$ORT_AAR" -d "$ORT_EXTRACT" >/dev/null

# Per-ABI shared libs → jniLibs/<ABI>/libonnxruntime.so (Gradle auto-packages)
for abi in armeabi-v7a arm64-v8a x86 x86_64; do
  if [ -f "$ORT_EXTRACT/jni/$abi/libonnxruntime.so" ]; then
    mkdir -p "$ANDROID_JNI/$abi"
    cp "$ORT_EXTRACT/jni/$abi/libonnxruntime.so" "$ANDROID_JNI/$abi/"
  else
    echo "warn: missing $abi in ORT AAR" >&2
  fi
done

# Headers → native_opencv/android/src/main/cpp/onnxruntime/include/
# (referenced by native_opencv/android/CMakeLists.txt target_include_directories)
mkdir -p "$ANDROID_ORT_INC"
cp -R "$ORT_EXTRACT/headers/." "$ANDROID_ORT_INC/"

echo "dun :)"
