#import <UIKit/UIKit.h>
#import <GRPCClient/GRPCCall+ChannelArg.h>
#import <GRPCClient/GRPCCall+Tests.h>
#import <opentracing/OTReference.h>

#import "LSClockState.h"
#import "LSSpan.h"
#import "LSSpanContext.h"
#import "LSTracer.h"
#import "LSUtil.h"
#import "LSVersion.h"
#import "Collector.pbrpc.h"

static NSString* kHostAddress = @"localhost:9997";

NSString* const LSDefaultHostport = @"collector.lightstep.com:443";

static const int kDefaultFlushIntervalSeconds = 30;
static const NSUInteger kDefaultMaxBufferedSpans = 5000;
static const NSUInteger kDefaultMaxPayloadJSONLength = 32 * 1024;

NSString *const LTSErrorDomain = @"com.lightstep";
NSInteger LTSBackgroundTaskError = 1;

static LSTracer* s_sharedInstance = nil;

@implementation LSTracer {
    NSString* m_accessToken;
    UInt64 m_runtimeGuid;
    LTSTracer* m_protoTracer;
    LSClockState* m_clockState;

    BOOL m_enabled;
    LTSCollectorService* m_collectorStub;
    NSMutableArray<LTSSpan*>* m_pendingProtoSpans;
    dispatch_queue_t m_flushQueue;
    dispatch_source_t m_flushTimer;
    NSDate* m_lastFlush;

    UIBackgroundTaskIdentifier m_bgTaskId;
}

@synthesize maxSpanRecords = m_maxSpanRecords;
@synthesize maxPayloadJSONLength = m_maxPayloadJSONLength;

- (instancetype) initWithToken:(NSString*)accessToken
                 componentName:(NSString*)componentName
                      hostport:(NSString*)hostport
          flushIntervalSeconds:(NSUInteger)flushIntervalSeconds
                  insecureGRPC:(BOOL)insecureGRPC
{
    if (self = [super init]) {
        self->m_accessToken = accessToken;
        self->m_runtimeGuid = [LSUtil generateGUID];
        
        // Populate m_protoTracer. Start with the tracerTags.
        NSMutableArray<LTSKeyValue*>* tracerTags = [NSMutableArray<LTSKeyValue*> array];
        {
            // All string-valued tags.
            NSDictionary* tracerStringTags = @{@"lightstep.tracer_platform": @"ios",
                                               @"lightstep.tracer_platform_version": [[UIDevice currentDevice] systemVersion],
                                               @"lightstep.tracer_version": LS_TRACER_VERSION,
                                               @"lightstep.component_name": componentName,
                                               @"device_model": [[UIDevice currentDevice] model]};
            for (NSString* key in tracerStringTags) {
                LTSKeyValue* elt = [[LTSKeyValue alloc] init];
                elt.key = key;
                elt.stringValue = [tracerStringTags objectForKey:key];
                [tracerTags addObject:elt];
            }
        }
        LTSTracer* protoTracer = [[LTSTracer alloc] init];
        protoTracer.tracerId = self->m_runtimeGuid;
        protoTracer.tagsArray = tracerTags;
        self->m_protoTracer = protoTracer;

        self->m_maxSpanRecords = kDefaultMaxBufferedSpans;
        self->m_maxPayloadJSONLength = kDefaultMaxPayloadJSONLength;
        self->m_pendingProtoSpans = [NSMutableArray<LTSSpan*> array];
        self->m_flushQueue = dispatch_queue_create("com.lightstep.flush_queue", DISPATCH_QUEUE_SERIAL);
        self->m_flushTimer = nil;
        self->m_enabled = true;  // if false, no longer collect tracing data
        self->m_clockState = [[LSClockState alloc] initWithLSTracer:self];
        self->m_lastFlush = [NSDate date];
        self->m_bgTaskId = UIBackgroundTaskInvalid;

        if (insecureGRPC) {
            [GRPCCall useInsecureConnectionsForHost:hostport];
        }
        [GRPCCall setUserAgentPrefix:@"LightStepTracerObjC/1.0" forHost:hostport];
        m_collectorStub = [[LTSCollectorService alloc] initWithHost:hostport];

        [self _forkFlushLoop:flushIntervalSeconds];
    }
    return self;
}

- (instancetype) initWithToken:(NSString*)accessToken
                 componentName:(nullable NSString*)componentName
          flushIntervalSeconds:(NSUInteger)flushIntervalSeconds {
    return [self initWithToken:accessToken
                 componentName:componentName
                      hostport:LSDefaultHostport
          flushIntervalSeconds:flushIntervalSeconds
                  insecureGRPC:false];
}

- (instancetype) initWithToken:(NSString*)accessToken
                    componentName:(NSString*)componentName {
    return [self initWithToken:accessToken
                 componentName:componentName
                      hostport:LSDefaultHostport
          flushIntervalSeconds:kDefaultFlushIntervalSeconds
                  insecureGRPC:false];
}

- (instancetype) initWithToken:(NSString*)accessToken {
    NSString* bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey];
    return [self initWithToken:accessToken componentName:bundleName];
}

- (id<OTSpan>)startSpan:(NSString*)operationName {
    return [self startSpan:operationName childOf:nil tags:nil startTime:[NSDate date]];
}

- (id<OTSpan>)startSpan:(NSString*)operationName
                   tags:(NSDictionary*)tags {
    return [self startSpan:operationName childOf:nil tags:tags startTime:[NSDate date]];
}

- (id<OTSpan>)startSpan:(NSString*)operationName
                childOf:(id<OTSpanContext>)parent {
    return [self startSpan:operationName childOf:parent tags:nil  startTime:[NSDate date]];
}

- (id<OTSpan>)startSpan:(NSString*)operationName
                childOf:(id<OTSpanContext>)parent
                   tags:(NSDictionary*)tags {
    return [self startSpan:operationName childOf:parent tags:tags startTime:[NSDate date]];
}

- (id<OTSpan>)startSpan:(NSString*)operationName
                childOf:(id<OTSpanContext>)parent
                   tags:(NSDictionary*)tags
              startTime:(NSDate*)startTime {
    return [self startSpan:operationName
                references:@[[OTReference childOf:parent]]
                      tags:tags
                 startTime:startTime];
}

- (id<OTSpan>)startSpan:(NSString*)operationName
             references:(NSArray*)references
                   tags:(NSDictionary*)tags
              startTime:(NSDate*)startTime {
    LSSpanContext* parent = nil;
    if (references != nil) {
        for (OTReference* ref in references) {
            if (ref != nil &&
                    ([ref.type isEqualToString:OTReferenceChildOf] ||
                     [ref.type isEqualToString:OTReferenceFollowsFrom])) {
                parent = (LSSpanContext*)ref.referencedContext;
            }
        }
    }
    // No locking required
    return [[LSSpan alloc] initWithTracer:self
                            operationName:operationName
                                   parent:parent
                                     tags:tags
                                startTime:startTime];
    return nil;
}

- (BOOL)inject:(id<OTSpanContext>)span format:(NSString*)format carrier:(id)carrier {
    return [self inject:span format:format carrier:carrier error:nil];
}

// These strings are used for TextMap inject and join.
static NSString* kBasicTracerStatePrefix   = @"ot-tracer-";
static NSString* kTraceIdKey               = @"ot-tracer-traceid";
static NSString* kSpanIdKey                = @"ot-tracer-spanid";
static NSString* kSampledKey               = @"ot-tracer-sampled";
static NSString* kBasicTracerBaggagePrefix = @"ot-baggage-";

- (BOOL)inject:(id<OTSpanContext>)spanContext format:(NSString*)format carrier:(id)carrier error:(NSError* __autoreleasing *)outError {
    LSSpanContext *ctx = (LSSpanContext*)spanContext;
    if ([format isEqualToString:OTFormatTextMap] ||
        [format isEqualToString:OTFormatHTTPHeaders]) {
        NSMutableDictionary *dict = carrier;
        [dict setObject:ctx.hexTraceId forKey:kTraceIdKey];
        [dict setObject:ctx.hexSpanId forKey:kSpanIdKey];
        [dict setObject:@"true" forKey:kSampledKey];
        // TODO: HTTP headers require special treatment here.
        [ctx forEachBaggageItem:^BOOL (NSString* key, NSString* val) {
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

- (id<OTSpanContext>)extractWithFormat:(NSString*)format carrier:(id)carrier {
    return [self extractWithFormat:format carrier:carrier error:nil];
}

- (id<OTSpanContext>)extractWithFormat:(NSString*)format carrier:(id)carrier error:(NSError* __autoreleasing *)outError {
    if ([format isEqualToString:OTFormatTextMap]) {
        NSMutableDictionary *dict = carrier;
        NSMutableDictionary *baggage;
        int foundRequiredFields = 0;
        UInt64 traceId = 0;
        UInt64 spanId = 0;
        for (NSString* key in dict) {
            if ([key hasPrefix:kBasicTracerBaggagePrefix]) {
                [baggage setObject:[dict objectForKey:key] forKey:[key substringFromIndex:kBasicTracerBaggagePrefix.length]];
            } else if ([key hasPrefix:kBasicTracerStatePrefix]) {
                if ([key isEqualToString:kTraceIdKey]) {
                    foundRequiredFields++;
                    traceId = [LSUtil guidFromHex:[dict objectForKey:key]];
                    if (traceId == 0) {
                        if (outError != nil) {
                            *outError = [NSError errorWithDomain:OTErrorDomain code:OTSpanContextCorruptedCode userInfo:nil];
                        }
                        return nil;
                    }
                } else if ([key isEqualToString:kSpanIdKey]) {
                    foundRequiredFields++;
                    spanId = [LSUtil guidFromHex:[dict objectForKey:key]];
                    if (spanId == 0) {
                        if (outError != nil) {
                            *outError = [NSError errorWithDomain:OTErrorDomain code:OTSpanContextCorruptedCode userInfo:nil];
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

- (NSString*) accessToken {
    @synchronized(self) {
        return m_accessToken;
    }
}

- (NSUInteger) maxSpanRecords {
    @synchronized(self) {
        return m_maxSpanRecords;
    }
}

- (void) setMaxSpanRecords:(NSUInteger)capacity {
    @synchronized(self) {
        m_maxSpanRecords = capacity;
    }
}


- (BOOL) enabled {
    @synchronized(self) {
        return m_enabled;
    }
}

- (void) _appendSpanRecord:(LTSSpan*)span {
    @synchronized(self) {
        if (!m_enabled) {
            return;
        }

        if (m_pendingProtoSpans.count < m_maxSpanRecords) {
            [m_pendingProtoSpans addObject:span];
        }
    }
}

// Establish the m_flushTimer ticker.
- (void) _forkFlushLoop:(NSUInteger)flushIntervalSeconds {
    @synchronized(self) {
        if (!m_enabled) {
            // Noop.
            return;
        }
        if (flushIntervalSeconds == 0) {
            // Noop.
            return;
        }
        m_flushTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, m_flushQueue);
        if (!m_flushTimer) {
            return;
        }
        dispatch_source_set_timer(m_flushTimer, DISPATCH_TIME_NOW,
                                  flushIntervalSeconds * NSEC_PER_SEC,
                                  NSEC_PER_SEC);
        __weak __typeof__(self) weakSelf = self;
        dispatch_source_set_event_handler(m_flushTimer, ^{
            [weakSelf flush:nil];
        });
        dispatch_resume(m_flushTimer);
    }
}

- (void)flush:(void (^)(NSError * _Nullable error))doneCallback {
    if (!m_enabled) {
        // Short-circuit.
        return;
    }

    LTSReportRequest *req = [LTSReportRequest message];
    req.auth = [[LTSAuth alloc] init];
    req.auth.accessToken = m_accessToken;
    req.tracer = [m_protoTracer copy];

    // We really want this flush to go through, even if the app enters the
    // background and iOS wants to move on with its life.
    //
    // NOTES ABOUT THE BACKGROUND TASK: we store m_bgTaskId in a member, which
    // means that it's important we don't call this function recursively (and
    // thus overwrite/lose the background task id). There is a recursive-"ish"
    // aspect to this function, as rpcBlock calls _refreshStub on error which
    // enqueues a call to flushToService on m_queue. m_queue is serialized,
    // though, so we are guaranteed that only one flushToService call will be
    // extant at any given moment, and thus it's safe to store the background
    // task id in m_bgTaskId.
    __weak __typeof__(self) weakSelf = self;
    void (^cleanupBlock)(NSError* _Nullable) = ^(NSError* _Nullable error) {
        [weakSelf _endBackgroundTask];
        if (doneCallback) {
            doneCallback(error);
        }
    };

    @synchronized(self) {
        NSDate* now = [NSDate date];
        req.internalMetrics.startTimestamp = [LSUtil protoTimestampFromMicros:m_lastFlush];
        req.internalMetrics.durationMicros = now.toMicros - m_lastFlush.toMicros;
        req.spansArray = m_pendingProtoSpans;
        req.timestampOffsetMicros = m_clockState.offsetMicros;
        m_pendingProtoSpans = [NSMutableArray<LTSSpan*> array];
        m_lastFlush = now;
        
        m_bgTaskId = [[UIApplication sharedApplication]
                      beginBackgroundTaskWithName:@"com.lightstep.flush"
                      expirationHandler:^{
                          cleanupBlock([NSError errorWithDomain:LTSErrorDomain code:LTSBackgroundTaskError userInfo:nil]);
                      }];
        if (m_bgTaskId == UIBackgroundTaskInvalid) {
            NSLog(@"unable to enter the background, so skipping flush");
            cleanupBlock([NSError errorWithDomain:LTSErrorDomain code:LTSBackgroundTaskError userInfo:nil]);
            return;
        }
    }

    UInt64 originMicros = [LSClockState nowMicros];
    [m_collectorStub reportWithRequest:req handler:^(LTSReportResponse * _Nullable response, NSError * _Nullable error) {
        UInt64 destinationMicros = [LSClockState nowMicros];
        cleanupBlock(error);
        __typeof__(self) strongSelf = weakSelf;
        if (response != nil && strongSelf != nil) {
            @synchronized(strongSelf) {
                if (response.commandsArray_Count > 0) {
                    for (LTSCommand* comm in response.commandsArray) {
                        if (comm.disable == true) {
                            // Irrevocably disable this client.
                            m_enabled = false;
                        }
                    }
                }
                // Update our local NTP-lite clock state with the latest measurements.
                [strongSelf->m_clockState addSampleWithOriginMicros:originMicros
                                                      receiveMicros:[LSUtil microsFromProtoTimestamp:response.receiveTimestamp]
                                                     transmitMicros:[LSUtil microsFromProtoTimestamp:response.transmitTimestamp]
                                                  destinationMicros:destinationMicros];
            }
        }
    }];
}

// Called by flush() callbacks on a failed report.
//
// Note: do not call directly from outside flush().
- (void) _endBackgroundTask
{
    @synchronized(self) {
        if (m_bgTaskId != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:m_bgTaskId];
            m_bgTaskId = UIBackgroundTaskInvalid;
        }
    }
}

@end
