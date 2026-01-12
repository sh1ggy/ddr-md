# mkdir -p download
cd download

# wget -O opencv-4.12.0-android-sdk.zip https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-android-sdk.zip
# wget -O opencv-4.12.0-ios-framework.zip https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-ios-framework.zip

# unzip opencv-4.12.0-android-sdk.zip
# unzip opencv-4.12.0-ios-framework.zip

cp -r opencv2.framework ../../native_opencv/ios
cp -r OpenCV-android-sdk/sdk/native/jni/include ../../native_opencv
mkdir -p ../../native_opencv/android/src/main/jniLibs/
cp -r OpenCV-android-sdk/sdk/native/libs/* ../../native_opencv/android/src/main/jniLibs/
cp -r OpenCV-android-sdk/sdk/native/jni/include ../../native_opencv/android/src/main/jniLibs/

echo "dun :)"
