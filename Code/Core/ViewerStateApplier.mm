// MARK: - File: ViewerStateApplier.mm
//--------------------------------------------------
#import "VTKViewController.h"
#import <vtkCamera.h>

static inline double clamp01(double x) {
    if (x < 0.0) return 0.0;
    if (x > 1.0) return 1.0;
    return x;
}

@implementation VTKViewController (ViewerStateApplier)

- (void)applyViewerState:(NSDictionary<NSString*, id> *)state
                  render:(BOOL)performRender
              completion:(void(^)(void))completion {
    if (!state) { if (completion) completion(); return; }
    
    // 1) Core context switch
    NSString *seriesID = state[@"seriesID"];
    if (seriesID && ![seriesID isEqualToString:self.currentSeriesID]) {
        [self loadSeriesWithID:seriesID];
    }
    
    NSNumber *modeNum = state[@"renderingMode"];
    VTKRenderingMode targetMode = modeNum
    ? (VTKRenderingMode)modeNum.integerValue
    : (VTKRenderingMode)self.currentRenderingMode;
    
    if (modeNum) [self setRenderingMode:targetMode];
    
    // 2) Visualization parameters
    NSNumber *ww = state[@"windowWidth"];
    NSNumber *wl = state[@"windowLevel"];
    if (ww && wl) [self setWindowWidth:ww.doubleValue level:wl.doubleValue];
    
    NSDictionary *overlay = state[@"overlay"];
    NSNumber *includeOverlay = overlay[@"include"];
    if (includeOverlay) self.exportOverlaysEnabled = includeOverlay.boolValue;
    
    BOOL hasExplicitCamera = (state[@"camera"] != nil);
    
    // Slab: apply for MPR only (2D single-slice does not apply slab)
    NSDictionary *slab = state[@"slab"];
    if (targetMode == VTKRenderingModeMPR && slab && self.resliceMapper) {
        NSString *mode = slab[@"mode"] ?: @"none";
        double thicknessMm = [slab[@"thicknessMm"] doubleValue];
        
        if ([mode isEqualToString:@"none"] || thicknessMm <= 0.0) {
            self.resliceMapper->SetSlabThickness(0.0);
        } else {
            self.resliceMapper->SetSlabType((int)VTKSlabTypeForModeString(mode));
            self.resliceMapper->SetSlabThickness(thicknessMm);
        }
    }
    
    // 3) Orientation intent (MPR only; ignored when explicit camera is present)
    NSNumber *orientationIntent = state[@"orientationIntent"];
    if (targetMode == VTKRenderingModeMPR && orientationIntent && !hasExplicitCamera) {
        [self applyOrientationIntent:(VTKMPROrientation)orientationIntent.integerValue];
    }
    
    // 4) Final geometry and position
    void (^finish)(void) = ^{
        // 2D: sliceIndex only
        if (targetMode == VTKRenderingModeSlice2D) {
            NSNumber *sliceIndex = state[@"sliceIndex"];
            if (sliceIndex) [self setSliceIndex:sliceIndex.intValue];
        }
        
        // MPR: relative distance fraction along reslice axis (0..1), unless camera is explicit
        if (targetMode == VTKRenderingModeMPR && !hasExplicitCamera) {
            NSDictionary *mpr = [state[@"mpr"] isKindOfClass:NSDictionary.class] ? state[@"mpr"] : nil;
            NSNumber *dist = [mpr[@"distance"] isKindOfClass:NSNumber.class] ? mpr[@"distance"] : nil;
            if (dist) {
                // Matches your raw implementation conceptually.
                [self setMPRCameraDistanceFraction:clamp01(dist.doubleValue)];
            }
        }
        
        // Explicit camera restore (wins over orientation/distance)
        NSDictionary *camState = state[@"camera"];
        if (camState && self.renderer) {
            vtkCamera *cam = self.renderer->GetActiveCamera();
            
            NSArray *fp = camState[@"focalPoint"];
            NSArray *pos = camState[@"position"];
            NSArray *up = camState[@"viewUp"];
            NSNumber *scale = camState[@"parallelScale"];
            
            if (fp.count == 3 && pos.count == 3 && up.count == 3) {
                cam->SetFocalPoint([fp[0] doubleValue], [fp[1] doubleValue], [fp[2] doubleValue]);
                cam->SetPosition([pos[0] doubleValue], [pos[1] doubleValue], [pos[2] doubleValue]);
                cam->SetViewUp([up[0] doubleValue], [up[1] doubleValue], [up[2] doubleValue]);
            }
            if (scale) cam->SetParallelScale(scale.doubleValue);
            
            self.renderer->ResetCameraClippingRange();
        }
        
        if (performRender) [self render];
        if (completion) completion();
    };
    
    // 5) Data availability gating for MPR
    if (targetMode == VTKRenderingModeMPR) {
        [self ensureVolumeDataWithPriority:NSOperationQueuePriorityHigh
                                completion:^(__unused BOOL ok) {
            dispatch_async(dispatch_get_main_queue(), finish);
        }];
    } else {
        finish();
    }
}

@end
