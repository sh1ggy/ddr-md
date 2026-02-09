#import <Vision/Vision.h>
#import <UIKit/UIKit.h>
#include "ocr_wrapper.h"

OCRResult OCRWrapper::performOCR(const cv::Mat& image, const cv::Rect& roi) {
    OCRResult result;
    result.confidence = 0.0f;
    result.boundingBox = roi;
    
    @autoreleasepool {
        // Extract ROI
        cv::Mat roiImage = image(roi);
        
        // Convert OpenCV Mat to UIImage
        NSData *data = [NSData dataWithBytes:roiImage.data 
                                      length:roiImage.total() * roiImage.elemSize()];
        
        CGColorSpaceRef colorSpace;
        CGBitmapInfo bitmapInfo;
        
        if (roiImage.elemSize() == 1) {
            colorSpace = CGColorSpaceCreateDeviceGray();
            bitmapInfo = kCGImageAlphaNone;
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB();
            bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast;
        }
        
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
        
        CGImageRef imageRef = CGImageCreate(
            roiImage.cols,
            roiImage.rows,
            8,
            8 * roiImage.elemSize(),
            roiImage.step,
            colorSpace,
            bitmapInfo,
            provider,
            NULL,
            false,
            kCGRenderingIntentDefault
        );
        
        UIImage *uiImage = [UIImage imageWithCGImage:imageRef];
        
        CGImageRelease(imageRef);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(colorSpace);
        
        // Perform OCR using Vision
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] 
            initWithCompletionHandler:^(VNRequest *request, NSError *error) {
                if (error) {
                    NSLog(@"Vision OCR error: %@", error);
                    dispatch_semaphore_signal(semaphore);
                    return;
                }
                
                NSArray<VNRecognizedTextObservation *> *observations = request.results;
                if (observations.count > 0) {
                    VNRecognizedTextObservation *topObservation = observations.firstObject;
                    VNRecognizedText *recognizedText = [topObservation topCandidates:1].firstObject;
                    
                    if (recognizedText) {
                        result.text = std::string([recognizedText.string UTF8String]);
                        result.confidence = recognizedText.confidence;
                        
                        NSLog(@"Recognized: %@ (confidence: %.2f)", 
                              recognizedText.string, recognizedText.confidence);
                    }
                }
                
                dispatch_semaphore_signal(semaphore);
            }];
        
        // Configure for fast, accurate recognition
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = NO;
        request.recognitionLanguages = @[@"en-US"];
        
        // Perform the request
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] 
                                          initWithCGImage:uiImage.CGImage 
                                          options:@{}];
        
        NSError *error;
        [handler performRequests:@[request] error:&error];
        
        // Wait for completion (with timeout)
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }
    
    return result;
}
