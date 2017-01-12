#import <UIKit/UIKit.h>
#import <opentracing/OTReference.h>

#import "LSClockState.h"
#import "LSSpan.h"
#import "LSSpanContext.h"
#import "LSTracer.h"
#import "LSUtil.h"
#import "LSVersion.h"

static NSString *const LSDefaultBaseURLString = @"https://collector.lightstep.com:443/api/v0/reports";
static const int LSDefaultFlushIntervalSeconds = 30;
static const NSUInteger LSDefaultMaxBufferedSpans = 5000;
static const NSUInteger LSDefaultMaxPayloadJSONLength = 32 * 1024;
static const NSUInteger LSMaxRequestSize = 1024 * 1024 * 4; // 4MB
NSInteger const LSBackgroundTaskError = 1;
NSInteger const LSRequestTooLargeError = 2;
NSString *const LSErrorDomain = @"com.lightstep";

#pragma mark - Private properties

@interface LSTracer ()
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *pendingJSONSpans;
@property(nonatomic, strong, readonly) NSDictionary<NSString *, NSString *> *tracerJSON;
@property(nonatomic, strong, readonly) LSClockState *clockState;

@property(nonatomic, strong, readonly) dispatch_queue_t flushQueue;
@property(nonatomic, strong) dispatch_source_t flushTimer;
@property(nonatomic, strong) NSDate *lastFlush;
@property(nonatomic) UInt64 runtimeGuid;
@property(nonatomic) UIBackgroundTaskIdentifier bgTaskId;
@end

#pragma mark - Tracer implementation

@implementation LSTracer

- (instancetype)initWithToken:(NSString *)accessToken
                componentName:(NSString *)componentName
                      baseURL:(NSURL *)baseURL
         flushIntervalSeconds:(NSUInteger)flushIntervalSeconds {
    if (self = [super init]) {
        _accessToken = accessToken;
        _runtimeGuid = [LSUtil generateGUID];
        _maxSpanRecords = LSDefaultMaxBufferedSpans;
        _maxPayloadJSONLength = LSDefaultMaxPayloadJSONLength;
        _pendingJSONSpans = [NSMutableArray<NSDictionary *> array];
        _flushQueue = dispatch_queue_create("com.lightstep.flush_queue", DISPATCH_QUEUE_SERIAL);
        _flushTimer = nil;
        _enabled = true;
        _clockState = [[LSClockState alloc] init];
        _lastFlush = [NSDate date];
        _bgTaskId = UIBackgroundTaskInvalid;
        _baseURL = baseURL ?: [NSURL URLWithString:LSDefaultBaseURLString];
        _tracerJSON = @{
            @"guid": [LSUtil hexGUID:_runtimeGuid],
            @"attrs": [LSUtil keyValueArrayFromDictionary:@{
                @"lightstep.tracer_platform": @"ios",
                @"lightstep.tracer_platform_version": [[UIDevice currentDevice] systemVersion],
                @"lightstep.tracer_version": LS_TRACER_VERSION,
                @"lightstep.component_name": componentName,
                @"device_model": [[UIDevice currentDevice] model]
            }]
        };

        [self _forkFlushLoop:flushIntervalSeconds];
    }
    return self;
}

- (instancetype)initWithToken:(NSString *)accessToken
                componentName:(nullable NSString *)componentName
         flushIntervalSeconds:(NSUInteger)flushIntervalSeconds {
    return [self initWithToken:accessToken
                 componentName:componentName
                       baseURL:nil
          flushIntervalSeconds:flushIntervalSeconds];
}

- (instancetype)initWithToken:(NSString *)accessToken componentName:(NSString *)componentName {
    return [self initWithToken:accessToken
                 componentName:componentName
                       baseURL:nil
          flushIntervalSeconds:LSDefaultFlushIntervalSeconds];
}

- (instancetype)initWithToken:(NSString *)accessToken {
    NSString *bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString *)kCFBundleNameKey];
    return [self initWithToken:accessToken componentName:bundleName];
}

- (id<OTSpan>)startSpan:(NSString *)operationName {
    return [self startSpan:operationName childOf:nil tags:nil startTime:[NSDate date]];
}

- (id<OTSpan>)startSpan:(NSString *)operationName tags:(NSDictionary *)tags {
    return [self startSpan:operationName childOf:nil tags:tags startTime:[NSDate date]];
}

- (id<OTSpan>)startSpan:(NSString *)operationName childOf:(id<OTSpanContext>)parent {
    return [self startSpan:operationName childOf:parent tags:nil startTime:[NSDate date]];
}

- (id<OTSpan>)startSpan:(NSString *)operationName childOf:(id<OTSpanContext>)parent tags:(NSDictionary *)tags {
    return [self startSpan:operationName childOf:parent tags:tags startTime:[NSDate date]];
}

- (id<OTSpan>)startSpan:(NSString *)operationName
                childOf:(id<OTSpanContext>)parent
                   tags:(NSDictionary *)tags
              startTime:(NSDate *)startTime {
    return [self startSpan:operationName references:@[[OTReference childOf:parent]] tags:tags startTime:startTime];
}

- (id<OTSpan>)startSpan:(NSString *)operationName
             references:(NSArray *)references
                   tags:(NSDictionary *)tags
              startTime:(NSDate *)startTime {
    LSSpanContext *parent = nil;
    if (references != nil) {
        for (OTReference *ref in references) {
            if (ref != nil &&
                ([ref.type isEqualToString:OTReferenceChildOf] || [ref.type isEqualToString:OTReferenceFollowsFrom])) {
                parent = (LSSpanContext *)ref.referencedContext;
            }
        }
    }
    // No locking required
    return [[LSSpan alloc] initWithTracer:self operationName:operationName parent:parent tags:tags startTime:startTime];
    return nil;
}

- (BOOL)inject:(id<OTSpanContext>)span format:(NSString *)format carrier:(id)carrier {
    return [self inject:span format:format carrier:carrier error:nil];
}

// These strings are used for TextMap inject and join.
static NSString *kBasicTracerStatePrefix = @"ot-tracer-";
static NSString *kTraceIdKey = @"ot-tracer-traceid";
static NSString *kSpanIdKey = @"ot-tracer-spanid";
static NSString *kSampledKey = @"ot-tracer-sampled";
static NSString *kBasicTracerBaggagePrefix = @"ot-baggage-";

- (BOOL)inject:(id<OTSpanContext>)spanContext
        format:(NSString *)format
       carrier:(id)carrier
         error:(NSError *__autoreleasing *)outError {
    LSSpanContext *ctx = (LSSpanContext *)spanContext;
    if ([format isEqualToString:OTFormatTextMap] || [format isEqualToString:OTFormatHTTPHeaders]) {
        NSMutableDictionary *dict = carrier;
        [dict setObject:ctx.hexTraceId forKey:kTraceIdKey];
        [dict setObject:ctx.hexSpanId forKey:kSpanIdKey];
        [dict setObject:@"true" forKey:kSampledKey];
        // TODO: HTTP headers require special treatment here.
        [ctx forEachBaggageItem:^BOOL(NSString *key, NSString *val) {
          [dict setObject:val forKey:key];
          return true;
        }];
        return true;
    } else if ([format isEqualToString:OTFormatBinary]) {
        // TODO: support the binary carrier here.
        if (outError != nil) {
            *outError = [NSError errorWithDomain:OTErrorDomain code:OTUnsupportedFormatCode userInfo:nil];
        }
        return false;
    } else {
        if (outError != nil) {
            *outError = [NSError errorWithDomain:OTErrorDomain code:OTUnsupportedFormatCode userInfo:nil];
        }
        return false;
    }
}

- (id<OTSpanContext>)extractWithFormat:(NSString *)format carrier:(id)carrier {
    return [self extractWithFormat:format carrier:carrier error:nil];
}

- (id<OTSpanContext>)extractWithFormat:(NSString *)format
                               carrier:(id)carrier
                                 error:(NSError *__autoreleasing *)outError {
    if ([format isEqualToString:OTFormatTextMap]) {
        NSMutableDictionary *dict = carrier;
        NSMutableDictionary *baggage;
        int foundRequiredFields = 0;
        UInt64 traceId = 0;
        UInt64 spanId = 0;
        for (NSString *key in dict) {
            if ([key hasPrefix:kBasicTracerBaggagePrefix]) {
                [baggage setObject:[dict objectForKey:key]
                            forKey:[key substringFromIndex:kBasicTracerBaggagePrefix.length]];
            } else if ([key hasPrefix:kBasicTracerStatePrefix]) {
                if ([key isEqualToString:kTraceIdKey]) {
                    foundRequiredFields++;
                    traceId = [LSUtil guidFromHex:[dict objectForKey:key]];
                    if (traceId == 0) {
                        if (outError != nil) {
                            *outError =
                                [NSError errorWithDomain:OTErrorDomain code:OTSpanContextCorruptedCode userInfo:nil];
                        }
                        return nil;
                    }
                } else if ([key isEqualToString:kSpanIdKey]) {
                    foundRequiredFields++;
                    spanId = [LSUtil guidFromHex:[dict objectForKey:key]];
                    if (spanId == 0) {
                        if (outError != nil) {
                            *outError =
                                [NSError errorWithDomain:OTErrorDomain code:OTSpanContextCorruptedCode userInfo:nil];
                        }
                        return nil;
                    }
                } else if ([key isEqualToString:kSampledKey]) {
                    // TODO: care about sampled status at this layer
                }
            }
        }
        if (foundRequiredFields == 0) {
            // (no error per se, just didn't find a trace to join)
            return nil;
        }
        if (foundRequiredFields < 2) {
            if (outError != nil) {
                *outError = [NSError errorWithDomain:OTErrorDomain code:OTSpanContextCorruptedCode userInfo:nil];
            }
            return nil;
        }

        return [[LSSpanContext alloc] initWithTraceId:traceId spanId:spanId baggage:baggage];
    } else if ([format isEqualToString:OTFormatBinary]) {
        if (outError != nil) {
            *outError = [NSError errorWithDomain:OTErrorDomain code:OTUnsupportedFormatCode userInfo:nil];
        }
        return nil;
    } else {
        if (outError != nil) {
            *outError = [NSError errorWithDomain:OTErrorDomain code:OTUnsupportedFormatCode userInfo:nil];
        }
        return nil;
    }
}

- (void)_appendSpanJSON:(NSDictionary *)spanJSON {
    @synchronized(self) {
        if (!self.enabled) {
            return;
        }

        if (self.pendingJSONSpans.count < self.maxSpanRecords) {
            [self.pendingJSONSpans addObject:spanJSON];
        }
    }
}

// Establish the m_flushTimer ticker.
- (void)_forkFlushLoop:(NSUInteger)flushIntervalSeconds {
    @synchronized(self) {
        if (!self.enabled) {
            // Noop.
            return;
        }
        if (flushIntervalSeconds == 0) {
            // Noop.
            return;
        }
        self.flushTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.flushQueue);
        if (!self.flushTimer) {
            return;
        }
        dispatch_source_set_timer(self.flushTimer, DISPATCH_TIME_NOW, flushIntervalSeconds * NSEC_PER_SEC,
                                  NSEC_PER_SEC);
        __weak __typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(self.flushTimer, ^{
          [weakSelf flush:nil];
        });
        dispatch_resume(self.flushTimer);
    }
}

- (void)flush:(void (^)(NSError *_Nullable error))doneCallback {
    if (!self.enabled) {
        // Short-circuit.
        return;
    }

    // We really want this flush to go through, even if the app enters the
    // background and iOS wants to move on with its life.
    //
    // NOTES ABOUT THE BACKGROUND TASK: we store _bgTaskId in a member, which
    // means that it's important we don't call this function recursively (and
    // thus overwrite/lose the background task id). There is a recursive-"ish"
    // aspect to this function, as rpcBlock calls _refreshStub on error which
    // enqueues a call to flushToService on m_queue. m_queue is serialized,
    // though, so we are guaranteed that only one flushToService call will be
    // extant at any given moment, and thus it's safe to store the background
    // task id in _bgTaskId.
    __weak __typeof(self) weakSelf = self;
    void (^cleanupBlock)(BOOL, NSError *_Nullable) = ^(BOOL endBackgroundTask, NSError *_Nullable error) {
      if (endBackgroundTask) {
          [weakSelf _endBackgroundTask];
      }
      if (doneCallback) {
          doneCallback(error);
      }
    };

    NSMutableDictionary *reqJSON;
    @synchronized(self) {
        NSDate *now = [NSDate date];
        if (self.pendingJSONSpans.count == 0) {
            // Nothing to report.
            return;
        }

        // reqJSON spec:
        // https://github.com/lightstep/lightstep-tracer-go/blob/40cbd138e6901f0dafdd0cccabb6fc7c5a716efb/lightstep_thrift/ttypes.go#L2586
        reqJSON = [NSMutableDictionary dictionary];
        reqJSON[@"timestamp_offset_micros"] = @(self.clockState.offsetMicros);
        reqJSON[@"runtime"] = self.tracerJSON;
        reqJSON[@"span_records"] = self.pendingJSONSpans;
        reqJSON[@"oldest_micros"] = @([self.lastFlush toMicros]);
        reqJSON[@"youngest_micros"] = @([now toMicros]);

        self.pendingJSONSpans = [NSMutableArray<NSDictionary *> array];
        self.lastFlush = now;

        self.bgTaskId = [[UIApplication sharedApplication]
            beginBackgroundTaskWithName:@"com.lightstep.flush"
                      expirationHandler:^{
                        cleanupBlock(true,
                                     [NSError errorWithDomain:LSErrorDomain code:LSBackgroundTaskError userInfo:nil]);
                      }];
        if (self.bgTaskId == UIBackgroundTaskInvalid) {
            NSLog(@"unable to enter the background, so skipping flush");
            cleanupBlock(false, [NSError errorWithDomain:LSErrorDomain code:LSBackgroundTaskError userInfo:nil]);
            return;
        }
    }

    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfiguration.HTTPAdditionalHeaders =
        @{ @"LightStep-Access-Token": self.accessToken,
           @"Content-Type": @"application/json" };
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
    NSString *reqBody = [LSUtil objectToJSONString:reqJSON maxLength:LSMaxRequestSize];
    if (reqBody == nil) {
        cleanupBlock(true, [NSError errorWithDomain:LSErrorDomain code:LSRequestTooLargeError userInfo:nil]);
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.baseURL];
    request.HTTPBody = [reqBody dataUsingEncoding:NSUTF8StringEncoding];
    request.HTTPMethod = @"POST";
    SInt64 originMicros = [LSClockState nowMicros];
    NSURLSessionDataTask *postDataTask =
        [session dataTaskWithRequest:request
                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                     @try {
                         __typeof(self) strongSelf = weakSelf;
                         SInt64 destinationMicros = [LSClockState nowMicros];
                         NSError *jsonError;
                         NSDictionary *responseJSON =
                             [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
                         if (jsonError == nil) {
                             if ([responseJSON objectForKey:@"timing"] != nil) {
                                 NSDictionary *timingJSON = [responseJSON objectForKey:@"timing"];
                                 NSNumber *receiveMicros = [timingJSON objectForKey:@"receive_micros"];
                                 NSNumber *transmitMicros = [timingJSON objectForKey:@"transmit_micros"];

                                 if (receiveMicros != nil && transmitMicros != nil) {
                                     // Update our local NTP-lite clock state with the latest
                                     // measurements.
                                     [strongSelf.clockState addSampleWithOriginMicros:originMicros
                                                                        receiveMicros:receiveMicros.longLongValue
                                                                       transmitMicros:transmitMicros.longLongValue
                                                                    destinationMicros:destinationMicros];
                                 }
                             }
                         }
                     } @catch (NSException *e) {
                         NSLog(@"Caught exception in LightStep reporting response; dropping "
                               @"data. Exception: %@",
                               e);
                     } @finally {
                         cleanupBlock(true, error);
                     }
                   }];
    // "Start" (resume) the HTTP activity.
    [postDataTask resume];
}

// Called by flush() callbacks on a failed report.
//
// Note: do not call directly from outside flush().
- (void)_endBackgroundTask {
    @synchronized(self) {
        if (self.bgTaskId != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:self.bgTaskId];
            self.bgTaskId = UIBackgroundTaskInvalid;
        }
    }
}

@end
