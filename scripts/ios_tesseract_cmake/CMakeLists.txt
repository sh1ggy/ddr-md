# CMakeLists.txt for building Tesseract + Leptonica + libjpeg + libpng
# as STATIC libraries for iOS arm64.
#
# Invoked by scripts/build_tesseract_ios.sh — not used directly.

cmake_minimum_required(VERSION 3.15)
project(tesseract_ios C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_C_STANDARD 11)

# SRC_BASE is passed in via -D from the build script and points to
# native_opencv/android/src/main/cpp
if(NOT DEFINED SRC_BASE)
    message(FATAL_ERROR "SRC_BASE must be set to the path of native_opencv/android/src/main/cpp")
endif()

# ── libjpeg (static) ────────────────────────────────────────────────
set(JPEG_SRC_DIR "${SRC_BASE}/libjpeg/src")
# Explicit file list matching Android CMakeLists to avoid platform-specific sources
add_library(jpeg STATIC
    ${JPEG_SRC_DIR}/jaricom.c
    ${JPEG_SRC_DIR}/jcapimin.c
    ${JPEG_SRC_DIR}/jcapistd.c
    ${JPEG_SRC_DIR}/jcarith.c
    ${JPEG_SRC_DIR}/jccoefct.c
    ${JPEG_SRC_DIR}/jccolor.c
    ${JPEG_SRC_DIR}/jcdctmgr.c
    ${JPEG_SRC_DIR}/jchuff.c
    ${JPEG_SRC_DIR}/jcinit.c
    ${JPEG_SRC_DIR}/jcmainct.c
    ${JPEG_SRC_DIR}/jcmarker.c
    ${JPEG_SRC_DIR}/jcmaster.c
    ${JPEG_SRC_DIR}/jcomapi.c
    ${JPEG_SRC_DIR}/jcparam.c
    ${JPEG_SRC_DIR}/jcprepct.c
    ${JPEG_SRC_DIR}/jcsample.c
    ${JPEG_SRC_DIR}/jctrans.c
    ${JPEG_SRC_DIR}/jdapimin.c
    ${JPEG_SRC_DIR}/jdapistd.c
    ${JPEG_SRC_DIR}/jdarith.c
    ${JPEG_SRC_DIR}/jdatadst.c
    ${JPEG_SRC_DIR}/jdatasrc.c
    ${JPEG_SRC_DIR}/jdcoefct.c
    ${JPEG_SRC_DIR}/jdcolor.c
    ${JPEG_SRC_DIR}/jddctmgr.c
    ${JPEG_SRC_DIR}/jdhuff.c
    ${JPEG_SRC_DIR}/jdinput.c
    ${JPEG_SRC_DIR}/jdmainct.c
    ${JPEG_SRC_DIR}/jdmarker.c
    ${JPEG_SRC_DIR}/jdmaster.c
    ${JPEG_SRC_DIR}/jdmerge.c
    ${JPEG_SRC_DIR}/jdpostct.c
    ${JPEG_SRC_DIR}/jdsample.c
    ${JPEG_SRC_DIR}/jdtrans.c
    ${JPEG_SRC_DIR}/jerror.c
    ${JPEG_SRC_DIR}/jfdctflt.c
    ${JPEG_SRC_DIR}/jfdctfst.c
    ${JPEG_SRC_DIR}/jfdctint.c
    ${JPEG_SRC_DIR}/jidctflt.c
    ${JPEG_SRC_DIR}/jidctfst.c
    ${JPEG_SRC_DIR}/jidctint.c
    ${JPEG_SRC_DIR}/jquant1.c
    ${JPEG_SRC_DIR}/jquant2.c
    ${JPEG_SRC_DIR}/jutils.c
    ${JPEG_SRC_DIR}/jmemmgr.c
    ${JPEG_SRC_DIR}/jmemansi.c
)
target_include_directories(jpeg PUBLIC "${JPEG_SRC_DIR}")

# ── libpng (static) ─────────────────────────────────────────────────
set(PNG_SRC_DIR "${SRC_BASE}/libpng/src")
# Explicit file list matching Android CMakeLists
add_library(pngx STATIC
    ${PNG_SRC_DIR}/png.c
    ${PNG_SRC_DIR}/pngerror.c
    ${PNG_SRC_DIR}/pngget.c
    ${PNG_SRC_DIR}/pngmem.c
    ${PNG_SRC_DIR}/pngpread.c
    ${PNG_SRC_DIR}/pngread.c
    ${PNG_SRC_DIR}/pngrio.c
    ${PNG_SRC_DIR}/pngrtran.c
    ${PNG_SRC_DIR}/pngrutil.c
    ${PNG_SRC_DIR}/pngset.c
    ${PNG_SRC_DIR}/pngtrans.c
    ${PNG_SRC_DIR}/pngwio.c
    ${PNG_SRC_DIR}/pngwrite.c
    ${PNG_SRC_DIR}/pngwtran.c
    ${PNG_SRC_DIR}/pngwutil.c
    ${PNG_SRC_DIR}/arm/arm_init.c
    ${PNG_SRC_DIR}/arm/filter_neon_intrinsics.c
    ${PNG_SRC_DIR}/arm/palette_neon_intrinsics.c
)
target_include_directories(pngx PUBLIC "${PNG_SRC_DIR}")
target_link_libraries(pngx z)

# ── leptonica (static) ──────────────────────────────────────────────
set(LEPT_SRC_DIR "${SRC_BASE}/leptonica/src/src")
set(LEPT_BASE_DIR "${SRC_BASE}/leptonica")

# Generate endianness header (iOS arm64 is little-endian, same as the template)
configure_file(
    "${LEPT_BASE_DIR}/endianness.h.in"
    "${LEPT_SRC_DIR}/endianness.h"
    @ONLY
)

file(GLOB LEPT_SRCS "${LEPT_SRC_DIR}/*.c")
# Only pure C leptonica sources — no Android JNI wrappers (.cpp files in parent dir)
add_library(leptonica STATIC ${LEPT_SRCS})
target_include_directories(leptonica PUBLIC "${LEPT_SRC_DIR}")
target_include_directories(leptonica PRIVATE "${JPEG_SRC_DIR}" "${PNG_SRC_DIR}")
target_compile_definitions(leptonica PRIVATE
    OS_IOS
    HAVE_LIBJPEG=1
    HAVE_LIBPNG=1
    HAVE_LIBZ=1
)
target_compile_options(leptonica PRIVATE "-Wno-address-of-packed-member")
target_link_libraries(leptonica jpeg pngx z)

# ── tesseract (static) ──────────────────────────────────────────────
set(TESS_BASE_DIR "${SRC_BASE}/tesseract")
set(TESS_SRC_DIR  "${TESS_BASE_DIR}/src/src")
set(TESS_INC_DIR  "${TESS_BASE_DIR}/src/include")

# Read version
file(STRINGS "${TESS_BASE_DIR}/src/VERSION" TESS_VERSION_PLAIN)
string(REGEX REPLACE "^([^.]*)\\..*" "\\1" VERSION_MAJOR ${TESS_VERSION_PLAIN})
string(REGEX REPLACE "^[^.]*\\.([^.]*)\\..*" "\\1" VERSION_MINOR ${TESS_VERSION_PLAIN})
string(REGEX REPLACE "^[^.]*\\.[^.]*\\.([0-9]*).*" "\\1" VERSION_PATCH ${TESS_VERSION_PLAIN})
set(PACKAGE_VERSION ${TESS_VERSION_PLAIN})
set(GENERIC_MAJOR_VERSION ${VERSION_MAJOR})
set(GENERIC_MINOR_VERSION ${VERSION_MINOR})
set(GENERIC_MICRO_VERSION ${VERSION_PATCH})

# Generate config headers
configure_file(
    "${TESS_INC_DIR}/tesseract/version.h.in"
    "${TESS_INC_DIR}/tesseract/version.h"
    @ONLY
)
configure_file(
    "${TESS_BASE_DIR}/config_auto.h.in"
    "${TESS_SRC_DIR}/api/config_auto.h"
    @ONLY
)

file(GLOB TESS_API_SRCS     "${TESS_SRC_DIR}/api/*.cpp")
file(GLOB TESS_CCMAIN_SRCS  "${TESS_SRC_DIR}/ccmain/*.cpp")
file(GLOB TESS_CCSTRUCT_SRCS "${TESS_SRC_DIR}/ccstruct/*.cpp")
file(GLOB TESS_CCUTIL_SRCS  "${TESS_SRC_DIR}/ccutil/*.cpp")
file(GLOB TESS_CLASSIFY_SRCS "${TESS_SRC_DIR}/classify/*.cpp")
file(GLOB TESS_CUTIL_SRCS   "${TESS_SRC_DIR}/cutil/*.cpp")
file(GLOB TESS_DICT_SRCS    "${TESS_SRC_DIR}/dict/*.cpp")
file(GLOB TESS_LSTM_SRCS    "${TESS_SRC_DIR}/lstm/*.cpp")
file(GLOB TESS_OPENCL_SRCS  "${TESS_SRC_DIR}/opencl/*.cpp")
file(GLOB TESS_TEXTORD_SRCS "${TESS_SRC_DIR}/textord/*.cpp")
file(GLOB TESS_VIEWER_SRCS  "${TESS_SRC_DIR}/viewer/*.cpp")
file(GLOB TESS_WORDREC_SRCS "${TESS_SRC_DIR}/wordrec/*.cpp")

# Arch files — include NEON since iOS arm64 always has NEON
set(TESS_ARCH_SRCS
    "${TESS_SRC_DIR}/arch/dotproduct.cpp"
    "${TESS_SRC_DIR}/arch/simddetect.cpp"
    "${TESS_SRC_DIR}/arch/intsimdmatrix.cpp"
    "${TESS_SRC_DIR}/arch/intsimdmatrixneon.cpp"
    "${TESS_SRC_DIR}/arch/dotproductneon.cpp"
)

# NOTE: JNI wrappers (pageiterator.cpp, resultiterator.cpp, tessbaseapi.cpp)
# are Android-only and require <jni.h>. Excluded from iOS build.

add_library(tesseract STATIC
    ${TESS_API_SRCS}
    ${TESS_CCMAIN_SRCS}
    ${TESS_CCSTRUCT_SRCS}
    ${TESS_CCUTIL_SRCS}
    ${TESS_CLASSIFY_SRCS}
    ${TESS_CUTIL_SRCS}
    ${TESS_DICT_SRCS}
    ${TESS_LSTM_SRCS}
    ${TESS_OPENCL_SRCS}
    ${TESS_TEXTORD_SRCS}
    ${TESS_VIEWER_SRCS}
    ${TESS_WORDREC_SRCS}
    ${TESS_ARCH_SRCS}
)

target_include_directories(tesseract PUBLIC
    "${TESS_INC_DIR}"
)
target_include_directories(tesseract PRIVATE
    "${LEPT_SRC_DIR}"
    "${TESS_SRC_DIR}/api"
    "${TESS_SRC_DIR}/arch"
    "${TESS_SRC_DIR}/ccmain"
    "${TESS_SRC_DIR}/ccstruct"
    "${TESS_SRC_DIR}/ccutil"
    "${TESS_SRC_DIR}/classify"
    "${TESS_SRC_DIR}/cutil"
    "${TESS_SRC_DIR}/dict"
    "${TESS_SRC_DIR}/lstm"
    "${TESS_SRC_DIR}/opencl"
    "${TESS_SRC_DIR}/textord"
    "${TESS_SRC_DIR}/viewer"
    "${TESS_SRC_DIR}/wordrec"
)

target_compile_definitions(tesseract PRIVATE
    HAVE_CONFIG_H
    GRAPHICS_DISABLED
    FAST_FLOAT
    HAVE_NEON
)

target_compile_options(tesseract PRIVATE "-Wno-null-dereference")
target_link_libraries(tesseract leptonica)
