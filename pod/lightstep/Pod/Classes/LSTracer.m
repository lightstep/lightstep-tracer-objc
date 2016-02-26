//
//  LSTracer.m
//

#import <UIKit/UIKit.h>
#import "LSTracer.h"
#import "LSSpan.h"
#import "LSUtil.h"
#import "LSClockState.h"
#import "TBinaryProtocol.h"
#import "THTTPClient.h"
#import "TSocketClient.h"
#import "TTransportException.h"

NSString*const LSDefaultLightStepReportingHostport = @"collector.lightstep.com:443";

static NSString* kDefaultEndUserIdKey = @"end_user_id";
static const int kFlushIntervalSeconds = 30;
static const NSUInteger kDefaultMaxBufferedSpans = 5000;
static const NSUInteger kDefaultMaxBufferedLogs = 10000;

@implementation LSTracer {
    NSDate* m_startTime;
    NSString* m_accessToken;
    NSString* m_runtimeGuid;
    RLRuntime* m_runtimeInfo;
    LSClockState* m_clockState;

    NSString* m_serviceUrl;
    RLReportingServiceClient* m_serviceStub;
    bool m_enabled;
    float m_refreshStubDelaySecs;  // if kFirstRefreshDelay, we've never tried to refresh.
    NSMutableArray* m_pendingSpanRecords;
    NSMutableArray* m_pendingLogRecords;
    dispatch_queue_t m_queue;
    dispatch_source_t m_flushTimer;

    UIBackgroundTaskIdentifier m_bgTaskId;
}

@synthesize maxLogRecords = m_maxLogRecords;
@synthesize maxSpanRecords = m_maxSpanRecords;

static LSTracer* s_sharedInstance = nil;
static float kFirstRefreshDelay = 0;

- (instancetype) initWithServiceHostport:(NSString*)hostport token:(NSString*)accessToken groupName:(NSString*)groupName
{
    if (self = [super init]) {
        self.endUserKeyName = kDefaultEndUserIdKey;
        self->m_serviceUrl = [NSString stringWithFormat:@"https://%@/_rpc/v1/reports/binary", hostport];
        self->m_accessToken = accessToken;
        self->m_runtimeGuid = [LSUtil generateGUID];
        self->m_startTime = [NSDate date];
        NSMutableArray* runtimeAttrs = @[[[RLKeyValue alloc] initWithKey:@"cruntime_platform" Value:@"cocoa"],
                                         [[RLKeyValue alloc] initWithKey:@"ios_version" Value:[[UIDevice currentDevice] systemVersion]],
                                         [[RLKeyValue alloc] initWithKey:@"device_model" Value:[[UIDevice currentDevice] model]]].mutableCopy;
        self->m_runtimeInfo = [[RLRuntime alloc]
                               initWithGuid:self->m_runtimeGuid
                               start_micros:[m_startTime toMicros]
                               group_name:groupName
                               attrs:runtimeAttrs];

        self->m_maxLogRecords = kDefaultMaxBufferedLogs;
        self->m_maxSpanRecords = kDefaultMaxBufferedSpans;
        self->m_pendingSpanRecords = [NSMutableArray array];
        self->m_pendingLogRecords = [NSMutableArray array];
        self->m_queue = dispatch_queue_create("com.resonancelabs.signal.rpc", DISPATCH_QUEUE_SERIAL);
        self->m_flushTimer = nil;
        self->m_refreshStubDelaySecs = kFirstRefreshDelay;
        self->m_enabled = true;  // depends on the remote kill-switch.
        self->m_clockState = [[LSClockState alloc] initWithLSTracer:self];
        self->m_bgTaskId = UIBackgroundTaskInvalid;
        [self _refreshStub];
    }
    return self;
}

+ (instancetype) sharedInstanceWithServiceHostport:(NSString*)hostport token:(NSString*)accessToken groupName:(NSString*)groupName {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_sharedInstance = [[super alloc] initWithServiceHostport:hostport token:accessToken groupName:groupName];
    });
    return s_sharedInstance;
}

+ (instancetype) sharedInstanceWithAccessToken:(NSString*)accessToken groupName:(NSString*)groupName {
    return [LSTracer sharedInstanceWithServiceHostport:LSDefaultLightStepReportingHostport token:accessToken groupName:groupName];
}

+ (instancetype) sharedInstanceWithAccessToken:(NSString*)accessToken {
    NSString* runtimeGroupName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey];
    return [LSTracer sharedInstanceWithAccessToken:accessToken groupName:runtimeGroupName];
}

+ (LSTracer*) sharedInstance {
    if (s_sharedInstance == nil) {
        NSLog(@"Must call sharedInstanceWithAccessToken: before calling sharedInstance:!");
    }
    return s_sharedInstance;
}

- (LSSpan*)startSpan:(NSString*)operationName {
    return [self startSpan:operationName parent:nil tags:nil startTime:[NSDate date]];
}

- (LSSpan*)startSpan:(NSString*)operationName
                tags:(NSDictionary*)tags {
    return [self startSpan:operationName parent:nil tags:tags startTime:[NSDate date]];
}

- (LSSpan*)startSpan:(NSString*)operationName
              parent:(LSSpan*)parentSpan {
    return [self startSpan:operationName parent:parentSpan tags:nil  startTime:[NSDate date]];
}

- (LSSpan*)startSpan:(NSString*)operationName
              parent:(LSSpan*)parentSpan
                tags:(NSDictionary*)tags {
    return [self startSpan:operationName parent:parentSpan tags:tags startTime:[NSDate date]];
}

- (LSSpan*)startSpan:(NSString*)operationName
              parent:(LSSpan*)parentSpan
                tags:(NSDictionary*)tags
           startTime:(NSDate*)startTime {
    LSSpan* span = [[LSSpan alloc] initWithTracer:self
                                    operationName:operationName
                                           parent:parentSpan
                                             tags:tags
                                        startTime:startTime];
    return span;
}

- (NSObject*)injector:(NSString*)format {
    // TODO: implement this
    return nil;

}

- (NSObject*)extractor:(NSString*)format {
    // TODO: implement this
    return nil;
}



- (NSString*) serviceUrl {
    return m_serviceUrl;
}

- (NSString*) runtimeGuid {
    return m_runtimeGuid;
}

- (NSUInteger) maxLogRecords {
    return m_maxLogRecords;
}

- (void) setMaxLogRecords:(NSUInteger)capacity {
    m_maxLogRecords = capacity;
}

- (NSUInteger) maxSpanRecords {
    return m_maxLogRecords;
}

- (void) setMaxSpanRecords:(NSUInteger)capacity {
    m_maxSpanRecords = capacity;
}


- (bool) enabled {
    return m_enabled;
}

- (void) _appendSpanRecord:(RLSpanRecord*)sr {
    if (!m_enabled) {
        // Drop sr.
        return;
    }

    @synchronized(self) {
        if (m_pendingSpanRecords.count < m_maxSpanRecords) {
            [m_pendingSpanRecords addObject:sr];
        }
    }
}

- (void) _appendLogRecord:(RLLogRecord*)lr {
    if (!m_enabled) {
        // Drop lr.
        return;
    }

    @synchronized(self) {
        if (m_pendingLogRecords.count < m_maxLogRecords) {
            [m_pendingLogRecords addObject:lr];
        }
    }
}

static NSString* jsonStringForDictionary(NSDictionary* dict) {
    if (dict == nil) {
        return nil;
    }
    NSError* error;
    NSData* jsonData;
    @try {
        jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
    } @catch (NSException* e) {
        return @"<invalid dict input for json conversation>";
    }

    if (!jsonData) {
        NSLog(@"Could not encode JSON for dict: %@", error);
        return nil;
    } else {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
}

- (void) setEndUserId:(NSString*)endUserId {
    if (endUserId.length) {
        _endUserId = endUserId;
    } else {
        _endUserId = @"UNKNOWN";  // guard against bad callers
    }
}

- (void) _refreshStub
{
    if (!m_enabled) {
        // Noop.
        return;
    }

    if (m_serviceUrl == nil || m_serviceUrl.length == 0) {
        // Better safe than sorry (we don't think this should ever actually happen).
        return;
    }
    __weak __typeof__(self) weakSelf = self;
    void (^refreshBlock)() = ^{
        __typeof__(self) strongSelf = weakSelf;
        if (strongSelf) {
            if (strongSelf->m_flushTimer) {
                dispatch_source_cancel(strongSelf->m_flushTimer);
            }
            if (strongSelf->m_refreshStubDelaySecs == kFirstRefreshDelay) {
                // Don't actually sleep the first time we try to initiate m_serviceStub.
                strongSelf->m_refreshStubDelaySecs = 5;
            } else {
                // Exponential backoff with a 5-minute max.
                strongSelf->m_refreshStubDelaySecs = MIN(60*5, strongSelf->m_refreshStubDelaySecs * 1.5);
                NSLog(@"LSTracer backing off for %@ seconds", @(strongSelf->m_refreshStubDelaySecs));
                [NSThread sleepForTimeInterval:strongSelf->m_refreshStubDelaySecs];
            }

            NSObject<TTransport>* transport = [[THTTPClient alloc] initWithURL:[NSURL URLWithString:strongSelf->m_serviceUrl] userAgent:nil timeout:10];
            TBinaryProtocol* protocol = [[TBinaryProtocol alloc] initWithTransport:transport strictRead:YES strictWrite:YES];
            strongSelf->m_serviceStub = [[RLReportingServiceClient alloc] initWithProtocol:protocol];
            if (strongSelf->m_serviceStub) {
                // Restart the backoff.
                strongSelf->m_refreshStubDelaySecs = 5;

                // Initialize and "resume" (i.e., "start") the m_flushTimer.
                strongSelf->m_flushTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, strongSelf->m_queue);
                if (strongSelf->m_flushTimer) {
                    dispatch_source_set_timer(strongSelf->m_flushTimer, DISPATCH_TIME_NOW, kFlushIntervalSeconds * NSEC_PER_SEC, NSEC_PER_SEC);
                    dispatch_source_set_event_handler(strongSelf->m_flushTimer, ^{
                        __typeof__(self) reallyStrongSelf = weakSelf;
                        if (reallyStrongSelf) {
                            [reallyStrongSelf flush];
                        }
                    });
                    dispatch_resume(strongSelf->m_flushTimer);
                }
            }
        }
    };
    dispatch_async(m_queue, refreshBlock);
}

static void correctTimestamps(NSArray* logRecords, NSArray* spanRecords, micros_t offset) {
    for (int i = 0; i < logRecords.count; ++i) {
        RLLogRecord* curLog = logRecords[i];
        curLog.timestamp_micros += offset;
    }
    for (int i = 0; i < spanRecords.count; ++i) {
        RLSpanRecord* curSpan = spanRecords[i];
        curSpan.oldest_micros += offset;
        curSpan.youngest_micros += offset;
    }
}

- (void) flush {

    micros_t tsCorrection = m_clockState.offsetMicros;

    // TODO: there is not currently a good way to report this diagnostic
    // information
    /*if (tsCorrection != 0) {
        [self logEvent:@"cr/time_correction_state" payload:@{@"offset_micros": @(tsCorrection)}];
    }*/

    NSMutableArray* spansToFlush;
    NSMutableArray* logsToFlush;
    @synchronized(self) {
        spansToFlush = m_pendingSpanRecords;
        logsToFlush = m_pendingLogRecords;
        m_pendingSpanRecords = [NSMutableArray array];
        m_pendingLogRecords = [NSMutableArray array];
    }

    if (!m_enabled) {
        // Deliberately do this after clearing the pending records (just in case).
        return;
    }

    if (spansToFlush.count + logsToFlush.count == 0) {
        // Nothing to do.
        return;
    }

    if (m_bgTaskId != UIBackgroundTaskInvalid) {
        // Do not proceed if we are already flush()ing in the background.
        return;
    }

    void (^revertBlock)() = ^{
        @synchronized(self) {
            // We apparently failed to flush these records, so re-enqueue them
            // at the heads of m_pending*Records. This is a little sketchy
            // since we don't actually *know* if the peer service saw them or
            // not, but this is the more conservative path as far as data loss
            // is concerned.
            //
            // Don't forget to un-correct the timestamps.
            correctTimestamps(logsToFlush, spansToFlush, -tsCorrection);
            [m_pendingSpanRecords insertObjects:spansToFlush atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, spansToFlush.count)]];
            [m_pendingLogRecords insertObjects:logsToFlush atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, logsToFlush.count)]];
            if (m_bgTaskId != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:m_bgTaskId];
                m_bgTaskId = UIBackgroundTaskInvalid;
            }
        }
    };

    // We really want this flush to go through, even if the app enters the
    // background and iOS wants to move on with its life.
    //
    // NOTES ABOUT THE BACKGROUND TASK: we store m_bgTaskId is a member, which
    // means that it's important we don't call this function recursively (and
    // thus overwrite/lose the background task id). There is a recursive-"ish"
    // aspect to this function, as rpcBlock calls _refreshStub on error which
    // enqueues a call to flushToService on m_queue. m_queue is serialized,
    // though, so we are guaranteed that only one flushToService call will be
    // extant at any given moment, and thus it's safe to store the background
    // task id in m_bgTaskId.
    m_bgTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"reslabs_flush" expirationHandler:revertBlock];
    if (m_bgTaskId == UIBackgroundTaskInvalid) {
        NSLog(@"unable to enter the background, so skipping flush");
        revertBlock();
        return;
    }

    // Correct the timestamps just before building the RLReportRequest.
    correctTimestamps(logsToFlush, spansToFlush, tsCorrection);
    RLAuth* auth = [[RLAuth alloc] initWithAccess_token:m_accessToken];
    RLReportRequest* req = [[RLReportRequest alloc]
                            initWithRuntime:m_runtimeInfo
                            span_records:spansToFlush
                            log_records:logsToFlush
                            timestamp_offset_micros:tsCorrection
                            oldest_micros:0
                            youngest_micros:0
                            counters:nil];

    __weak __typeof__(self) weakSelf = self;
    void (^rpcBlock)() = ^{
        __typeof__(self) strongSelf = weakSelf;
        if (strongSelf) {
            void(^dropAndRecover)() = ^void() {
                // Try to start from scratch.
                //
                // Don't-call revertBlock() to avoid a client feedback loop.
                [strongSelf _refreshStub];
            };

            RLReportResponse* response = nil;
            @try {
                micros_t originMicros = [LSClockState nowMicros];
                response = [strongSelf->m_serviceStub Report:auth request:req];
                micros_t destinationMicros = [LSClockState nowMicros];
                for (RLCommand* command in response.commands) {
                    if (command.disable) {
                        NSLog(@"NOTE: Signal LSTracer disabled by remote peer.");
                        strongSelf->m_enabled = false;
                    }
                }
                if (response.timing.receive_microsIsSet && response.timing.transmit_microsIsSet) {
                    // Update our local NTP-lite clock state with the latest measurements.
                    [m_clockState addSampleWithOriginMicros:originMicros
                                              receiveMicros:response.timing.receive_micros
                                             transmitMicros:response.timing.transmit_micros
                                          destinationMicros:destinationMicros];
                }
            }
            @catch (TApplicationException* e)
            {
                NSLog(@"RPC exception %@: %@", [e name], [e description]);
                dropAndRecover();
            }
            @catch (TException* e)
            {
                // TTransportException, or unknown type of exception: drop data since "first, [we want to] do no harm."
                NSLog(@"Unknown Thrift error %@: %@", [e name], [e description]);
                dropAndRecover();
            }
            @catch (NSException* e)
            {
                // We really don't like catching NSException, but unfortunately
                // Thrift is sufficiently flaky that we will sleep better here
                // if we do.
                NSLog(@"Unexpected bad things happened %@: %@", [e name], [e description]);
                dropAndRecover();
            }
        }

        // We can safely end the background task at this point.
        [[UIApplication sharedApplication] endBackgroundTask:strongSelf->m_bgTaskId];
        strongSelf->m_bgTaskId = UIBackgroundTaskInvalid;
    };

    dispatch_async(m_queue, rpcBlock);
}

@end
