cmake_minimum_required(VERSION 3.4.1)


# Tesseract requires newer C++ standard, so let's enable it for all libraries
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include_directories(../include)
add_library(lib_opencv SHARED IMPORTED)

set_target_properties(lib_opencv PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/libopencv_java4.so)



find_library(log-lib log)

#This is adding our code and making it a library
add_library(native_opencv SHARED ../ios/Classes/native_opencv.cpp)

add_subdirectory(src/main/cpp/libjpeg)
add_subdirectory(src/main/cpp/libpng)
add_subdirectory(src/main/cpp/leptonica)
add_subdirectory(src/main/cpp/tesseract)

# This adds the required libraries for for our stuff
target_link_libraries(native_opencv tesseract lib_opencv ${log-lib})