// MARK: - File: SharedDataCache.mm
//--------------------------------------------------
#import "SharedDataCache.h"

@implementation SharedDataCache {
    NSMutableDictionary<NSString *, NSMutableArray *> *_sliceBuckets; // seriesID -> [SliceData|NSNull]
    NSMutableDictionary<NSString *, id> *_volumeStorage;              // seriesID -> volume object
    NSCountedSet<NSString *> *_owners;
    dispatch_queue_t _lockQueue;
}

- (instancetype)init {
    if ((self = [super init])) {
        _sliceBuckets = [NSMutableDictionary dictionary];
        _volumeStorage = [NSMutableDictionary dictionary];
        _owners = [[NSCountedSet alloc] init];
        _lockQueue = dispatch_queue_create("SharedDataCache.lock", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)retainSeries:(NSString *)seriesID expectedSliceCount:(NSUInteger)count {
    if (!seriesID) return;
    dispatch_sync(_lockQueue, ^{
        [_owners addObject:seriesID];
        
        if (!_sliceBuckets[seriesID]) {
            NSMutableArray *bucket = [NSMutableArray arrayWithCapacity:count];
            for (NSUInteger i = 0; i < count; ++i) {
                [bucket addObject:[NSNull null]];
            }
            _sliceBuckets[seriesID] = bucket;
        }
    });
}

- (void)releaseSeries:(NSString *)seriesID {
    if (!seriesID) return;
    dispatch_sync(_lockQueue, ^{
        NSUInteger count = [_owners countForObject:seriesID];
        
        if (count <= 1) {
            [_owners removeObject:seriesID];
            [_sliceBuckets removeObjectForKey:seriesID];
            [_volumeStorage removeObjectForKey:seriesID];
        } else {
            [_owners removeObject:seriesID];
        }
    });
}

- (void)setSliceData:(id)data forSeries:(NSString *)seriesID index:(NSUInteger)index {
    if (!seriesID) return;
    dispatch_sync(_lockQueue, ^{
        NSMutableArray *bucket = _sliceBuckets[seriesID];
        if (bucket && index < bucket.count) {
            if (bucket[index] == [NSNull null]) {
                bucket[index] = data ?: [NSNull null];
            }
        }
    });
}

- (id)sliceDataForSeries:(NSString *)seriesID index:(NSUInteger)index {
    if (!seriesID) return nil;
    
    __block id data = nil;
    dispatch_sync(_lockQueue, ^{
        NSArray *bucket = _sliceBuckets[seriesID];
        if (index < bucket.count) {
            id obj = bucket[index];
            if (obj != [NSNull null]) data = obj;
        }
    });
    return data;
}

- (void)setVolumeData:(id)volume forSeries:(NSString *)seriesID {
    if (!seriesID) return;
    dispatch_sync(_lockQueue, ^{
        _volumeStorage[seriesID] = volume;
    });
}

- (id)volumeDataForSeries:(NSString *)seriesID {
    if (!seriesID) return nil;
    
    __block id volume = nil;
    dispatch_sync(_lockQueue, ^{
        volume = _volumeStorage[seriesID];
    });
    return volume;
}

@end
