#ifdef __OBJC__
#import <Foundation/Foundation.h>
#undef YES
#undef NO
#endif

#include <opencv2/opencv.hpp>
#include "ocr_wrapper.h"

#ifdef __OBJC__
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#endif

#import <Vision/Vision.h>
#import <UIKit/UIKit.h>

void UIImageToMat(const UIImage *image, cv::Mat &m, bool alphaExist = false) {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width, rows = image.size.height;
    CGContextRef contextRef;
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
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
}

OCRResult OCRWrapper::performOCR(const uint8_t *data,
                                 int width,
                                 int height,
                                 int step,
                                 int channels)
{
    __block OCRResult result;
    result.confidence = 0.0f;
    
    @autoreleasepool
    {
        // --- Create CGImage from raw ROI buffer ---
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
        
        CGDataProviderRef provider =
        CGDataProviderCreateWithData(NULL, data, step * height, NULL);
        
        CGImageRef cgImage =
        CGImageCreate(width,
                      height,
                      8,              // bits per component
                      8,              // bits per pixel (gray)
                      step,           // bytes per row
                      colorSpace,
                      kCGImageAlphaNone,
                      provider,
                      NULL,
                      false,
                      kCGRenderingIntentDefault);
        
        CIImage *ciImage = [[CIImage alloc] initWithCGImage:cgImage];
        
        CGImageRelease(cgImage);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(colorSpace);
        
        // --- OCR ---
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        
        VNRecognizeTextRequest *request =
        [[VNRecognizeTextRequest alloc] initWithCompletionHandler:
         ^(VNRequest *request, NSError *error) {
            
            NSArray *observations = request.results;
            if (observations.count > 0)
            {
                VNRecognizedTextObservation *obs = observations.firstObject;
                VNRecognizedText *txt = [[obs topCandidates:1] firstObject];
                if (txt)
                {
                    result.text = std::string([txt.string UTF8String]);
                    result.confidence = txt.confidence;
                }
            }
            dispatch_semaphore_signal(sem);
        }];
        
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = NO;
        request.recognitionLanguages = @[ @"en-US" ];
        
        VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc] initWithCIImage:ciImage options:@{}];
        
        [handler performRequests:@[request] error:nil];
        
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    }
    
    return result;
}
