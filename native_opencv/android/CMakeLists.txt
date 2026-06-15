cmake_minimum_required(VERSION 3.4.1)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include_directories(../include)
add_library(lib_opencv SHARED IMPORTED)
set_target_properties(lib_opencv PROPERTIES IMPORTED_LOCATION
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/libopencv_java4.so)

# ONNX Runtime prebuilt shared library
add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES IMPORTED_LOCATION
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/libonnxruntime.so)

find_library(log-lib log)
# NDK Camera2 + media (AImageReader) + native window for the native camera path.
find_library(camera2ndk-lib camera2ndk)
find_library(mediandk-lib mediandk)
find_library(android-lib android)

add_library(native_opencv SHARED
    ../ios/Classes/native_opencv.cpp
    ../ios/Classes/ocr_onnx.cpp
    ../ios/Classes/ddrocr_instance.cpp
    ../ios/Classes/details_detector.cpp
    # Native camera capture + OCR pipeline (replaces the Flutter `camera` plugin)
    src/main/cpp/camera_ocr_session.cpp
    src/main/cpp/jni_bridge.cpp
)

target_include_directories(native_opencv PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/onnxruntime/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes
)

target_compile_definitions(native_opencv PUBLIC DART_SHARED_LIB)

if (ANDROID)
    target_link_options(native_opencv PRIVATE "-Wl,-z,max-page-size=16384")
endif()

target_link_libraries(native_opencv onnxruntime lib_opencv ${log-lib}
    ${camera2ndk-lib} ${mediandk-lib} ${android-lib})
