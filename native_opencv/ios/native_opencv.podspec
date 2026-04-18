#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint native_opencv.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'native_opencv'
  s.version          = '0.0.1'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m,mm,cpp,swift}'
  s.public_header_files = 'Classes/NativeOpencvPlugin.h'
  # Keep C++ headers out of the module umbrella so Swift/Clang won't try
  # to parse C++ headers when importing the module.
  s.private_header_files = 'Classes/ocr_wrapper.h', 'Classes/**/*.hpp'
  s.frameworks = 'AVFoundation', 'Vision', 'UIKit'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 arm64',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) FLUTTER_ROOT=\$(SRCROOT)/../.. HAVE_LIBJPEG=1 HAVE_LIBPNG=1 HAVE_LIBZ=1 HAVE_CONFIG_H GRAPHICS_DISABLED FAST_FLOAT OS_IOS',
    'CLANG_CXX_LANGUAGE_DIALECT' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/opencv2.framework/Headers" "${PODS_TARGET_SRCROOT}/libs/include" "${PODS_TARGET_SRCROOT}/libs/include/leptonica"'
  }
  s.swift_version = '5.0'

  # telling CocoaPods not to remove framework
  s.preserve_paths = 'opencv2.framework', 'libs'

  # telling linker to include opencv2 framework and Tesseract static libs
  s.xcconfig = { 'OTHER_LDFLAGS' => '-framework opencv2 -lz' }

  # including OpenCV framework
  s.vendored_frameworks = 'opencv2.framework' 

  # including Tesseract/Leptonica static libraries
  # NOTE: libjpeg and libpng are NOT listed here — opencv2.framework already
  # bundles both.  Linking a second copy causes duplicate-symbol collisions
  # that silently break imread/imdecode.
  s.vendored_libraries = 'libs/libtesseract.a', 'libs/libleptonica.a'

  # including C++ library
  s.library = 'c++'
end
