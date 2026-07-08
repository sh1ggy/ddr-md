cmake_minimum_required(VERSION 3.16)
project(model_compare CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# NDEBUG makes the pipeline's save_img() short-circuit, so the harness doesn't
# spray debug PNGs into assets/ on every run.
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()
add_compile_definitions(NDEBUG)

# Reuse the real pipeline sources unchanged.
set(CLASSES ${CMAKE_CURRENT_SOURCE_DIR}/../../ios/Classes)

add_executable(model_compare
    main.cpp
    ${CLASSES}/ddrocr_instance.cpp
    ${CLASSES}/ocr_onnx.cpp
    ${CLASSES}/details_detector.cpp
)

target_include_directories(model_compare PRIVATE ${CLASSES})

# --- OpenCV (brew) ---
find_package(OpenCV REQUIRED)
target_include_directories(model_compare PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(model_compare PRIVATE ${OpenCV_LIBS})

# --- onnxruntime (brew dynamic lib) ---
# The repo-shipped xcframework is a static CoreML-EP build that drags in
# protobuf/CoreML symbols; the brew dylib is a clean desktop build, so we link
# that for the offline harness. Headers come from brew's include dir.
find_library(ORT_LIB onnxruntime PATHS /opt/homebrew/lib REQUIRED)
find_path(ORT_INCLUDE onnxruntime_cxx_api.h
    PATHS /opt/homebrew/include /opt/homebrew/include/onnxruntime
          /opt/homebrew/Cellar/onnxruntime/*/include/onnxruntime
    REQUIRED)
target_include_directories(model_compare PRIVATE ${ORT_INCLUDE})
target_link_libraries(model_compare PRIVATE ${ORT_LIB})
