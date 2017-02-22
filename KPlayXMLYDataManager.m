//
//  KPlayXMLYDataManager.m
//  kartor3
//
//  Created by 沈希 on 16/4/13.
//  Copyright © 2016年 CST. All rights reserved.
//

#import "KPlayXMLYDataManager.h"
#import "QMSafeMutableDictionary.h"
#import "XMReqMgr.h"
static NSString* const kXMLYCacheFileName = @"kplay_ximalaya_data";
static NSString* const kXMLYAdCache = @"kpla_ximalaya_yadcache";
static NSString* const kXMKeySavedFlag = @"kXMKeySavedFlag";
static NSInteger maxCount = 200;  // 调用喜马拉雅获取音频时最多200，5.3版本时喜马拉雅规定

@interface KPlayXMLYDataManager ()
{
    dispatch_queue_t _ac_q;
}

@property (strong, nonatomic) QMSafeMutableDictionary *ximaDic;

@property (copy, nonatomic) NSString * adurls;  // 所有音频的url集合，url以逗号分隔开

@property (assign, atomic) BOOL isLoadBack;  // 调用喜马拉雅接口是否返回


@end

@implementation KPlayXMLYDataManager

@synthesize ximaDic = _ximaDic;

+ (instancetype)sharedInstance {
    
    static KPlayXMLYDataManager *__instance__;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        __instance__ = [self new];
        
    });
    
    return __instance__;
}


#pragma mark - init


- (instancetype)init
{
    self = [super init];
    if (self) {
        
        [self _init];
        
    }
    return self;
}


- (void)_init {
    
    _ac_q = dispatch_queue_create("kp.ximalaya.da.ac.q", DISPATCH_QUEUE_CONCURRENT);
    
    _xmlyInitSuccess =  [[NSUserDefaults standardUserDefaults] boolForKey:kXMKeySavedFlag];

    _isLoadBack = YES;
    
    _ximaDic = [QMSafeMutableDictionary new];
    
    [self _restore];
}


- (void) loadXMDataWithAdurls:(NSString *) adurls {
    if(adurls) {
        _adurls = adurls;
        [self loadXMData:_adurls];
    }
}

// 重新加载喜马拉雅频道播放对象
- (void) reloadXMData {
    if(_adurls) {
        [self loadXMData:_adurls];
    }
}

/**
 *  @param adurl 请求的id值
 */
-(void) loadXMData:(NSString *) adurl{
    if(_xmlyInitSuccess) {
        if(_isLoadBack && adurl) {
            NSArray *urlArr = [adurl componentsSeparatedByString:@","];
            if(urlArr.count > maxCount) {
                // 5.3版本添加
                [self loadBatchXMDataWithArr:urlArr];
            } else {
                _isLoadBack = NO;
                __weak typeof(self) weakSelf = self;
                [[XMReqMgr sharedInstance] requestXMData:XMReqType_TracksBatch params:@{@"ids":adurl} withCompletionHander:^(id result, XMErrorModel *error) {
                    if(!error) {
                        if(result && [result isKindOfClass:[NSDictionary class]]) {
                            NSArray *array = (NSArray *) result[@"tracks"];
                            // 如果返回的数量和请求的数量不等则不做任何处理
                            NSInteger reqCount = [adurl componentsSeparatedByString:@","].count;
                            if(array.count > 0) {
                                // 修改缓存内容
                                BOOL result = [weakSelf _updateXimaDicWithArr:array];
                                // 当缓存方式变化才本地序列化
                                if(result) {
                                    // 如果请求数等于返回数同时数量大于1则，覆盖本地序列化的数据，反之追加数据
                                    if(array && array.count == reqCount && array.count > 1) {
                                        // 本地序列化
                                        [weakSelf _save:array];
                                    } else {
                                        if(_ximaDic) {
                                            NSMutableArray *arr = [NSMutableArray new];
                                            NSArray *trackArr = _ximaDic.allValues;
                                            for(XMTrack *track in trackArr) {
                                                [arr addObject:[track toDictionary]];
                                            }
                                            // 本地序列化
                                            [weakSelf _save:arr];
                                        }
                                    }
                                }
                            }
                            KTRLogDebug(@"%@%lu%@%lu", @"请求喜马拉雅数量:", (unsigned long)reqCount, @" 成功返回数量:", (unsigned long)array.count);
                        }
                    } else {
                        KTRLogInfo(@"%@%@%@", @"喜马拉雅接口调用失败:", error.error_code, error.error_desc);
                    }
                    _isLoadBack = YES;
                }];
            }
        }
    } else {
       KTRLogError(@"%@", @"喜马拉雅XMReqMgr初始化失败");
    }
}

// 批量获取喜马拉雅音频 5.3版本添加
-(void) loadBatchXMDataWithArr:(NSArray *)urlArr {
    _isLoadBack = NO;
    __weak typeof(self) weakSelf = self;
    NSInteger reqNum = (urlArr.count%maxCount == 0) ? urlArr.count/maxCount : urlArr.count/maxCount + 1;
    NSMutableArray *trackArr = [[NSMutableArray alloc] init];
    dispatch_group_t _g = dispatch_group_create();
    for(int i=0; i<reqNum; i++) {
        NSArray *reqArr;
        if((i+1)*maxCount >= urlArr.count) {
            reqArr = [urlArr subarrayWithRange:NSMakeRange(i*maxCount, urlArr.count%maxCount)];
        } else {
            reqArr = [urlArr subarrayWithRange:NSMakeRange(i*maxCount, maxCount)];
        }
        dispatch_group_enter(_g);
        [[XMReqMgr sharedInstance] requestXMData:XMReqType_TracksBatch params:@{@"ids":[reqArr componentsJoinedByString:@","]} withCompletionHander:^(id result, XMErrorModel *error) {
            if(!error) {
                if(result && [result isKindOfClass:[NSDictionary class]]) {
                    NSArray *array = (NSArray *) result[@"tracks"];
                    if(array.count > 0) {
                        [trackArr addObjectsFromArray:array];
                    }
                    KTRLogDebug(@"%@%lu%@%lu", @"请求喜马拉雅数量:", (unsigned long)reqArr.count, @" 成功返回数量:", (unsigned long)array.count);
                }
            } else {
                KTRLogInfo(@"%@%@%@", @"喜马拉雅接口调用失败:", error.error_code, error.error_desc);
            }
            dispatch_group_leave(_g);
        }];
    }
    dispatch_group_notify(_g, dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            _isLoadBack = YES;
            // 修改缓存内容
            BOOL result = [weakSelf _updateXimaDicWithArr:trackArr];
            // 当缓存方式变化才本地序列化
            if(result) {
                // 本地序列化
                [weakSelf _save:trackArr];
            }
        });
    });

}

- (XMTrack *) selectXMModelWithAdurl:(NSString *) adurl {
    XMTrack *track = nil;
    if(adurl) {
        if(_ximaDic) {
            XMTrack *trackCache = [_ximaDic objectForKey:adurl];
            if(trackCache) {
                track = [[XMTrack alloc] initWithDictionary:[trackCache toDictionary]];
            } else {
                [self loadXMData:adurl];
            }
        } else {
           [self loadXMData:adurl];
        }
    }
    return track;
}

- (void) updateInitStatus:(BOOL) status {
    _xmlyInitSuccess = status;
    
    [[NSUserDefaults standardUserDefaults] setBool:_xmlyInitSuccess forKey:kXMKeySavedFlag];
    [[NSUserDefaults standardUserDefaults] synchronize];

}

#pragma mark - setter
-(void) setXimaDic:(QMSafeMutableDictionary *)ximaDic {
    if(ximaDic) {
        dispatch_barrier_async(_ac_q, ^{
            _ximaDic = ximaDic;
        });
    }
}

#pragma mark - getter
-(QMSafeMutableDictionary *) ximaDic {
    __block QMSafeMutableDictionary *dic;
    dispatch_sync(_ac_q, ^{
        dic = _ximaDic;
    });
    return dic ?: [QMSafeMutableDictionary new];
}

// 初始化序列化数据到内存
- (void) _restore {
    NSData *data = [[NSData alloc] initWithContentsOfFile:[self _cachePath:kXMLYCacheFileName]];
    NSKeyedUnarchiver *unArchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    NSArray *arr = [unArchiver decodeObjectForKey:kXMLYAdCache];
    if(arr.count > 0) {
        [self _updateXimaDicWithArr:arr];
        KTRLogDebug(@"%@%lu", @"喜马拉雅反序列化数据成功-----", (unsigned long)arr.count);
    } else {
        _ximaDic = [QMSafeMutableDictionary new];
    }
}

// 修改内存使用
- (BOOL) _updateXimaDicWithArr:(NSArray *) array {
    if(array) {
        // 修改缓存数据
        for(int i = 0; i < array.count; i++) {
            XMTrack *track;
            if([array[i] isKindOfClass:[NSDictionary class]]){
                NSDictionary *trackDic = (NSDictionary *)array[i];
                track = [[XMTrack alloc] initWithDictionary:trackDic];
                if(track) {
                    NSInteger trackId = track.trackId;
                    NSString *trackIdStr = _F(@"%ld", (long)trackId);
                    if(!_ximaDic) {
                        _ximaDic = [QMSafeMutableDictionary new];
                    }
                    if(![_ximaDic containsObject:track]) {
                        [_ximaDic setObject:track forKey:trackIdStr];
                    }
                }
            }
        }
    }
    return YES;
}

// 本地序列化数据
- (BOOL) _save:(NSArray *) arr {
    if(arr.count > 0) {
        NSMutableData *data = [[NSMutableData alloc] init];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
        [archiver encodeObject:arr forKey:kXMLYAdCache];
        [archiver finishEncoding];
        BOOL adFlag = [data writeToFile:[self _cachePath:kXMLYCacheFileName] atomically:YES];
        KTRLogError(@"%@%@%lu", @"喜马拉雅序列化数据", adFlag ? @"成功" : @"失败", (unsigned long)_ximaDic.allValues.count);
        return adFlag;
    }
    return NO;
}

- (NSString *)_cachePath:(NSString *)fileName {
    
    NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    return [cachePath stringByAppendingPathComponent:fileName];
    
}

- (void) test {
    NSArray *params = @[@"123",@"12471064"];
    NSString *ids = [params join:@","];
    
    XMReqMgr *mgr = [XMReqMgr sharedInstance];
    [mgr requestXMData:XMReqType_TracksBatch params:@{@"ids":ids} withCompletionHander:^(id result, XMErrorModel *error) {
        if(!error) {
            NSDictionary *dic = (NSDictionary *)result;
            NSArray *array = dic[@"tracks"];
            for(int i = 0; i < array.count; i++) {
                XMTrack *track;
                if([array[i] isKindOfClass:[XMTrack class]]) {
                    track = (XMTrack *)array[i];
                } else if([array[i] isKindOfClass:[NSDictionary class]]){
                    NSDictionary *trackDic = (NSDictionary *)array[i];
                    track = [[XMTrack alloc] initWithDictionary:trackDic];
                }
                NSInteger trackId = track.trackId;
                NSString *trackIdStr = _F(@"%ld", (long)trackId);
                KTRLogVerbose(@"%@", trackIdStr);
            }
        }
    }];
}

@end
