// MARK: - File: ViewerStateFactory.mm
//--------------------------------------------------
#import "VTKViewController.h"
#import <vtkCamera.h>
#import <vtkStringArray.h>

static inline NSString *VTKSlabModeStringForType(NSInteger slabType) {
    switch (slabType) {
        case 1: return @"mip";
        case 2: return @"minip";
        case 3: return @"average";
        default: return @"none";
    }
}

static inline NSInteger VTKSlabTypeForModeString(NSString *mode) {
    if ([mode isEqualToString:@"mip"])     return 1;
    if ([mode isEqualToString:@"minip"])   return 2;
    if ([mode isEqualToString:@"average"]) return 3;
    return 0;
}

static inline double clamp01(double x) {
    if (x < 0.0) return 0.0;
    if (x > 1.0) return 1.0;
    return x;
}

@implementation VTKViewController (ViewerStateFactory)

#pragma mark - Serialize (single current view)

- (NSDictionary<NSString*, id> *)serializeViewerState {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    
    if (self.currentSeriesID) state[@"seriesID"] = self.currentSeriesID;
    state[@"renderingMode"] = @(self.currentRenderingMode);
    
    // 2D uses sliceIndex; MPR uses a relative distance fraction along the reslice axis.
    if (self.currentRenderingMode == VTKRenderingModeSlice2D) {
        state[@"sliceIndex"] = @(self.currentSliceIndex);
    } else if (self.currentRenderingMode == VTKRenderingModeMPR) {
        // Assumes your controller maintains this as a 0..1 fraction (eg, updated whenever MPR navigation occurs).
        state[@"mpr"] = @{ @"distance": @(clamp01(self.currentMPRDistanceFraction)) };
    }
    
    if (self.renderer) {
        vtkCamera *cam = self.renderer->GetActiveCamera();
        double fp[3], pos[3], up[3];
        cam->GetFocalPoint(fp);
        cam->GetPosition(pos);
        cam->GetViewUp(up);
        
        state[@"camera"] = @{
            @"focalPoint": @[ @(fp[0]), @(fp[1]), @(fp[2]) ],
            @"position":   @[ @(pos[0]), @(pos[1]), @(pos[2]) ],
            @"viewUp":     @[ @(up[0]), @(up[1]), @(up[2]) ],
            @"parallelScale": @(cam->GetParallelScale())
        };
    }
    
    state[@"windowWidth"] = @(self.currentWindowWidth);
    state[@"windowLevel"] = @(self.currentWindowLevel);
    
    // Slab is an MPR concept in this sanitized architecture; omit for 2D slice mode.
    if (self.currentRenderingMode == VTKRenderingModeMPR) {
        state[@"slab"] = @{
            @"mode": (self.currentSlabModeString ?: @"none"),
            @"thicknessMm": @(self.currentSlabThicknessMm)
        };
    }
    
    state[@"overlay"] = @{ @"include": @(self.exportOverlaysEnabled) };
    
    return state;
}

#pragma mark - State generation (batch capture)

- (NSArray<NSDictionary<NSString*, id> *> *)minimal2DViewerStatesForCurrentSeriesWithMaxEntries:(NSInteger)maxEntries {
    if (!self.currentSeriesID) return @[];
    return [self minimal2DViewerStatesForSeriesID:self.currentSeriesID
                                       maxEntries:maxEntries
                                 samplingStrategy:0
                               centerBiasExponent:0.0];
}

- (NSArray<NSDictionary<NSString*, id> *> *)minimal2DViewerStatesForSeriesID:(NSString *)seriesID
                                                                  maxEntries:(NSInteger)maxEntries
                                                            samplingStrategy:(NSInteger)samplingStrategy
                                                          centerBiasExponent:(double)exponent {
    NSInteger sliceCount = [self sliceCountForSeriesID:seriesID];
    if (sliceCount <= 0) return @[];
    
    NSArray<NSNumber *> *indices =
    (samplingStrategy == 1 && exponent > 1.0)
    ? [self centerBiasedSliceIndicesForCount:sliceCount maxEntries:maxEntries exponent:exponent]
    : [self uniformSliceIndicesForCount:sliceCount maxEntries:maxEntries];
    
    if (indices.count == 0) return @[];
    
    NSMutableArray<NSDictionary<NSString*, id> *> *states = [NSMutableArray arrayWithCapacity:indices.count];
    for (NSNumber *n in indices) {
        [states addObject:@{
            @"renderingMode": @(VTKRenderingModeSlice2D),
            @"seriesID": seriesID,
            @"sliceIndex": n
        }];
    }
    return states.copy;
}

- (NSArray<NSDictionary<NSString*, id> *> *)mprViewerStatesForSeriesID:(NSString *)seriesID
                                                            maxEntries:(NSInteger)maxEntries
                                                     orientationIntent:(NSInteger)orientationIntent
                                                              slabType:(NSInteger)slabType
                                                       slabThicknessMm:(double)slabThicknessMm
                                                      samplingStrategy:(NSInteger)samplingStrategy
                                                    centerBiasExponent:(double)exponent {
    NSInteger sliceCount = [self sliceCountForSeriesID:seriesID];
    if (sliceCount <= 0) return @[];
    
    NSArray<NSNumber *> *indices =
    (samplingStrategy == 1 && exponent > 1.0)
    ? [self centerBiasedSliceIndicesForCount:sliceCount maxEntries:maxEntries exponent:exponent]
    : [self uniformSliceIndicesForCount:sliceCount maxEntries:maxEntries];
    
    if (indices.count == 0) return @[];
    
    BOOL includeOrientation = (orientationIntent != 0);
    BOOL includeSlab = (slabType != 0 && slabThicknessMm > 0.0);
    
    double denom = (sliceCount > 1) ? (double)(sliceCount - 1) : 1.0;
    
    NSMutableArray<NSDictionary<NSString*, id> *> *states = [NSMutableArray arrayWithCapacity:indices.count];
    for (NSNumber *n in indices) {
        double fraction = (denom > 0.0) ? ((double)n.integerValue / denom) : 0.0;
        fraction = clamp01(fraction);
        
        NSMutableDictionary<NSString*, id> *st = [@{
            @"renderingMode": @(VTKRenderingModeMPR),
            @"seriesID": seriesID,
            // MPR uses a relative distance fraction along the reslice axis (0..1), not sliceIndex.
            @"mpr": @{ @"distance": @(fraction) }
        } mutableCopy];
        
        if (includeOrientation) st[@"orientationIntent"] = @(orientationIntent);
        
        if (includeSlab) {
            st[@"slab"] = @{
                @"mode": VTKSlabModeStringForType(slabType),
                @"thicknessMm": @(slabThicknessMm)
            };
        }
        
        [states addObject:st];
    }
    return states.copy;
}

#pragma mark - Helpers (series + sampling)

- (NSInteger)sliceCountForSeriesID:(NSString *)seriesID {
    if (!seriesID || !self.dicomService) return 0;
    
    NSInteger sIdx = [self.dicomService indexForSeriesID:seriesID];
    if (sIdx < 0) return 0;
    
    vtkSmartPointer<vtkStringArray> names = [self.dicomService fileNamesForSeries:(int)sIdx];
    return names ? (NSInteger)names->GetNumberOfValues() : 0;
}

- (NSArray<NSNumber *> *)uniformSliceIndicesForCount:(NSInteger)totalSlices
                                          maxEntries:(NSInteger)maxEntries {
    if (totalSlices <= 0 || maxEntries <= 0) return @[];
    
    NSInteger K = MIN(maxEntries, totalSlices);
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:K];
    
    for (NSInteger j = 0; j < K; ++j) {
        NSInteger idx = (j == K - 1)
        ? (totalSlices - 1)
        : (NSInteger)floor((double)(j * totalSlices) / (double)K);
        
        idx = MAX(0, MIN(idx, totalSlices - 1));
        [out addObject:@(idx)];
    }
    return out;
}

- (NSArray<NSNumber *> *)centerBiasedSliceIndicesForCount:(NSInteger)totalSlices
                                               maxEntries:(NSInteger)maxEntries
                                                 exponent:(double)exponent {
    if (totalSlices <= 0 || maxEntries <= 0) return @[];
    
    NSInteger K = MIN(maxEntries, totalSlices);
    if (K == 1) return @[ @(totalSlices / 2) ];
    
    const double denom = (double)(totalSlices - 1);
    
    NSMutableOrderedSet<NSNumber *> *unique = [NSMutableOrderedSet orderedSetWithCapacity:K];
    
    for (NSInteger j = 0; j < K; ++j) {
        double u = (double)j / (double)(K - 1);        // [0..1]
        double t = 2.0 * u - 1.0;                      // [-1..1]
        double biasedT = (t >= 0.0 ? 1.0 : -1.0) * pow(fabs(t), exponent);
        double v = (biasedT + 1.0) * 0.5;              // [0..1]
        
        NSInteger idx = (NSInteger)floor(v * denom + 0.5);
        idx = MAX(0, MIN(idx, totalSlices - 1));
        [unique addObject:@(idx)];
    }
    
    [unique addObject:@(0)];
    [unique addObject:@(totalSlices - 1)];
    
    return [[unique array] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSInteger ia = a.integerValue, ib = b.integerValue;
        if (ia < ib) return NSOrderedAscending;
        if (ia > ib) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

@end
