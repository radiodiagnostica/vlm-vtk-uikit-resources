// MARK: - File: CapturePipeline.mm
//--------------------------------------------------
#import "VTKView.h"
#import <CoreVideo/CoreVideo.h>
#import <OpenGLES/ES3/gl.h>
#import <objc/runtime.h>

static const void *kOverlayDrawBlockKey = &kOverlayDrawBlockKey;

@implementation VTKView (CapturePipeline)

- (void)setOverlayDrawBlock:(void (^)(CGContextRef ctx, CGSize size))block {
    objc_setAssociatedObject(self, kOverlayDrawBlockKey, block, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void (^)(CGContextRef ctx, CGSize size))overlayDrawBlock {
    return objc_getAssociatedObject(self, kOverlayDrawBlockKey);
}

- (void)captureFrameWithWidth:(int)width
                       height:(int)height
                    sourceFBO:(GLint)sourceFBO
              overlaysEnabled:(BOOL)overlaysEnabled
                   completion:(void(^)(UIImage *))completion {
    
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, _snapshotFBO);
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER,
                           GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D,
                           CVOpenGLESTextureGetName(_targetTexture),
                           0);
    
    glBindFramebuffer(GL_READ_FRAMEBUFFER, sourceFBO);
    
    glBlitFramebuffer(0, 0, width, height,
                      0, 0, width, height,
                      GL_COLOR_BUFFER_BIT, GL_NEAREST);
    
    glFlush();
    
    CVPixelBufferRef pixelBuffer = _targetPixelBuffer;
    CVPixelBufferRetain(pixelBuffer);
    
    dispatch_async(_captureQueue, ^{
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        
        void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(baseAddress,
                                                     width,
                                                     height,
                                                     8,
                                                     bytesPerRow,
                                                     colorSpace,
                                                     kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        
        if (overlaysEnabled) {
            void (^block)(CGContextRef, CGSize) = self.overlayDrawBlock;
            if (block) block(context, CGSizeMake((CGFloat)width, (CGFloat)height));
        }
        
        CGImageRef cgImage = CGBitmapContextCreateImage(context);
        
        UIImage *result = [UIImage imageWithCGImage:cgImage
                                              scale:1.0
                                        orientation:UIImageOrientationUp];
        
        CGImageRelease(cgImage);
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferRelease(pixelBuffer);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    });
}

@end
