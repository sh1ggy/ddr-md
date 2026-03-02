#ifdef __OBJC__
#import <Foundation/Foundation.h>
#undef YES
#undef NO
#endif

#include <opencv2/opencv.hpp>
#include "ocr_wrapper.h"

#ifdef __OBJC__
#define YES ((BOOL)1)
#define NO  ((BOOL)0)
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

OCRResult OCRWrapper::performOCR(const cv::Mat& roiMat) {
    __block OCRResult result;
    result.confidence = 0.0f;
    //TODO zero out BoundingBox
    
    @autoreleasepool {
        // Convert OpenCV Mat to UIImage
        NSData *data = [NSData dataWithBytes:roiMat.data
                                      length:roiMat.elemSize()*roiMat.total()];
        
        CGColorSpaceRef colorSpace;
        CGBitmapInfo bitmapInfo;
        
        if (roiMat.elemSize() == 1) {
            colorSpace = CGColorSpaceCreateDeviceGray();
            //            bitmapInfo = kCGImageAlphaNone;
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB();
            //            bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast;
        }
        
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
        
        // Creating CGImage from cv::Mat
        CGImageRef imageRef = CGImageCreate(
                                            roiMat.cols, //width
                                            roiMat.rows, //height
                                            8, //bits per component
                                            8*roiMat.elemSize(), // bits per pixel
                                            roiMat.step.p[0], // bytesPerRow
                                            colorSpace, // colorspace
                                            kCGImageAlphaNone|kCGBitmapByteOrderDefault,// bitmap info
                                            provider, // CGDataProviderRef
                                            NULL, //decode
                                            false, //should interpolate
                                            kCGRenderingIntentDefault //intent
                                            );
        
        UIImage *uiImage = [UIImage imageWithCGImage:imageRef];
        
        CGImageRelease(imageRef);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(colorSpace);
        
        NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                                      inDomains:NSUserDomainMask] firstObject];
        NSString *documentsDirectory = [documentsURL path];
        NSData *dataToSave = UIImageJPEGRepresentation(uiImage, 1.0);
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *fullPath = [documentsDirectory stringByAppendingPathComponent:@"DEETroiImage.jpg"];
        [fileManager createFileAtPath:fullPath contents:dataToSave attributes:nil];
        
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
        request.recognitionLanguages = @[@"en-US", @"ja-JP"];
        
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
