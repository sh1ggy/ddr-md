#ifdef __OBJC__
#import <Foundation/Foundation.h>
#undef YES
#undef NO
#endif

#include "ocr_wrapper.h"
#include <opencv2/opencv.hpp>

#ifdef __OBJC__
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#endif

#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

void UIImageToMat(const UIImage *image, cv::Mat &m, bool alphaExist = false) {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width, rows = image.size.height;
    CGContextRef contextRef = nullptr;
    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast;
    if (CGColorSpaceGetModel(colorSpace) == 0) {
        m.create(rows, cols, CV_8UC1);
        // 8 bits per component, 1 channel
        bitmapInfo = kCGImageAlphaNone;
        if (!alphaExist) {
            bitmapInfo = kCGImageAlphaNone;
            contextRef = CGBitmapContextCreate(m.data, m.cols, m.rows, 8, m.step[0],
                                               colorSpace, bitmapInfo);
        } else {
            m.create(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
            if (!alphaExist) {
                bitmapInfo = kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault;
                contextRef = CGBitmapContextCreate(m.data, m.cols, m.rows, 8, m.step[0],
                                                   colorSpace, bitmapInfo);
            }
        }
    }
    if (contextRef) {
        CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
        CGContextRelease(contextRef);
    }
}

extern void platform_log(const char *fmt, ...);

OCRWrapper::OCRWrapper(std::string datapath) {
    platform_log("Ios OCRWrapper initialized\n");
}

OCRWrapper::~OCRWrapper() { platform_log("Ios OCRWrapper destroyed\n"); }

OCRResult OCRWrapper::performOCR(const cv::Mat &roiMat, OCRType ocrType, const std::string& roiName) {
    __block OCRResult result;
    result.confidence = 0.0f;
    // TODO zero out BoundingBox

    // roiMat is already a 0-255 Otsu-thresholded image (white text on
    // black background) — no rescaling required.
    cv::Mat mat;
    if (roiMat.depth() == CV_8U)
        mat = roiMat;
    else
        roiMat.convertTo(mat, CV_8U);
    
    @autoreleasepool {
        // Convert OpenCV Mat to UIImage
        NSData *data = [NSData dataWithBytes:mat.data
                                      length:mat.elemSize() * mat.total()];
        
        CGColorSpaceRef colorSpace;
        
        if (mat.elemSize() == 1) {
            colorSpace = CGColorSpaceCreateDeviceGray();
            //            bitmapInfo = kCGImageAlphaNone;
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB();
            //            bitmapInfo = kCGBitmapByteOrderDefault |
            //            kCGImageAlphaNoneSkipLast;
        }
        
        CGDataProviderRef provider =
        CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
        
        // Creating CGImage from cv::Mat
        CGImageRef imageRef = CGImageCreate(
                                            mat.cols,                             // width
                                            mat.rows,                             // height
                                            8,                                             // bits per component
                                            8 * mat.elemSize(),                   // bits per pixel
                                            mat.step.p[0],                        // bytesPerRow
                                            colorSpace,                                    // colorspace
                                            kCGImageAlphaNone | kCGBitmapByteOrderDefault, // bitmap info
                                            provider,                                      // CGDataProviderRef
                                            NULL,                                          // decode
                                            false,                                         // should interpolate
                                            kCGRenderingIntentDefault                      // intent
                                            );
        
        UIImage *uiImage = [UIImage imageWithCGImage:imageRef];
        
        CGImageRelease(imageRef);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(colorSpace);
        
        if (!debugDir.empty()) {
            NSString *debugDirNS = [NSString stringWithUTF8String:debugDir.c_str()];
            NSString *roiNameNS = [NSString stringWithUTF8String:roiName.c_str()];
            NSString *fullPath = [debugDirNS stringByAppendingPathComponent:
                                  [roiNameNS stringByAppendingString:@"_vision_input.jpg"]];
            NSData *dataToSave = UIImageJPEGRepresentation(uiImage, 1.0);
            [[NSFileManager defaultManager] createFileAtPath:fullPath contents:dataToSave attributes:nil];
            platform_log("[OCR] saved Vision input image: %s\n", [fullPath UTF8String]);
        }
        
        // Perform OCR using Vision
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc]
                                           initWithCompletionHandler:^(VNRequest *request, NSError *error) {
            if (error) {
                NSLog(@"Vision OCR error: %@", error);
                dispatch_semaphore_signal(semaphore);
                return;
            }
            
            NSArray<VNRecognizedTextObservation *> *observations =
            request.results;
            if (observations.count > 0) {
                VNRecognizedTextObservation *topObservation =
                observations.firstObject;
                VNRecognizedText *recognizedText =
                [topObservation topCandidates:1].firstObject;
                
                if (recognizedText) {
                    result.text = std::string([recognizedText.string UTF8String]);
                    result.confidence = recognizedText.confidence;
                    
                    NSLog(@"Recognized: %@ (confidence: %.2f)", recognizedText.string,
                          recognizedText.confidence);
                }
            }
            
            dispatch_semaphore_signal(semaphore);
        }];
        
        // Configure for fast, accurate recognition
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        
        switch (ocrType) {
            case OCRType::Digit:
                request.usesLanguageCorrection = NO;
                break;
            case OCRType::Eng:
                request.usesLanguageCorrection = YES;
                request.recognitionLanguages = @[ @"en-US" ];
                break;
            case OCRType::EngJP:
                request.usesLanguageCorrection = YES;
                request.recognitionLanguages = @[ @"en-US", @"ja-JP" ];
                break;
            default:
                break;
        }
        
        // Perform the request
        VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc] initWithCGImage:uiImage.CGImage
                                               options:@{}];
        
        NSError *error;
        [handler performRequests:@[ request ] error:&error];
        
        // Wait for completion (with timeout)
        dispatch_semaphore_wait(semaphore,
                                dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }
    
    return result;
}
