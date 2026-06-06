# TODO: replace this AI generated code with legit code one day.... 
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
add_library(native_opencv SHARED ../ios/Classes/native_opencv.cpp ../ios/Classes/ocr_tesseract.cpp  ../ios/Classes/ddrocr_instance.cpp ../ios/Classes/details_tracker.cpp )

add_subdirectory(src/main/cpp/libjpeg)
add_subdirectory(src/main/cpp/libpng)
add_subdirectory(src/main/cpp/leptonica)
add_subdirectory(src/main/cpp/tesseract)

# Add include directories for leptonica and tesseract
# leptonica headers live under src/src, and tesseract public headers are in include/tesseract
# Avoid adding whole source trees to prevent non-header files (like "version") from being picked up.
target_include_directories(native_opencv PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/leptonica/src/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/tesseract/src/include
)

target_compile_definitions(native_opencv PUBLIC DART_SHARED_LIB)

if (ANDROID)
    # Support Android 15 16k page size.
    target_link_options(native_opencv PRIVATE "-Wl,-z,max-page-size=16384")
endif()

# Link against the libraries we've built
target_link_libraries(native_opencv tesseract leptonica lib_opencv ${log-lib})
