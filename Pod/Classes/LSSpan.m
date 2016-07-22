#import "LSSpan.h"
#import "LSTracer.h"
#import "LSTracerInternal.h"
#import "LSUtil.h"

#pragma mark - LSSpan

@implementation LSSpan {
    LSTracer* m_tracer;
    UInt64 m_traceId;
    UInt64 m_spanId;
    NSString* m_operationName;
    NSDate* m_startTime;
    NSMutableDictionary* m_tags;
    NSMutableDictionary* m_baggage;
    bool m_errorFlag;
}

- (instancetype) initWithTracer:(LSTracer*)client {
    return [self initWithTracer:client
                  operationName:@""
                         parent:nil
                           tags:nil
                      startTime:nil];
}

- (instancetype) initWithTracer:(LSTracer*)tracer
                  operationName:(NSString*)operationName
                         parent:(LSSpan*)parent
                           tags:(NSDictionary*)tags
                      startTime:(NSDate*)startTime {
    UInt64 traceId = 0;
    UInt64 parentId = 0;
    if (parent != nil) {
        parentId = parent.spanId;
        traceId = parent.traceId;
    }
    return [self initWithTracer:tracer
                  operationName:operationName
                        traceId:traceId
                       parentId:parentId
                           tags:tags
                      startTime:startTime];
}

- (instancetype) initWithTracer:(LSTracer*)tracer
                  operationName:(NSString*)operationName
                        traceId:(UInt64)traceId
                       parentId:(UInt64)parentId
                           tags:(NSDictionary*)tags
                      startTime:(NSDate*)startTime {
    if (self = [super init]) {
        self->m_tracer = tracer;
        self->m_spanId = [LSUtil generateGUID];
        self->m_operationName = operationName;
        self->m_startTime = startTime;
        self->m_tags = [NSMutableDictionary dictionary];
        self->m_baggage = [NSMutableDictionary dictionary];
        self->m_errorFlag = false;

        if (startTime == nil) {
            m_startTime = [NSDate date];
        }
        if (parentId != 0) {
            [m_tags setObject:[LSUtil hexGUID:parentId] forKey:@"parent_span_guid"];
        }
        if (traceId == 0) {
            self->m_traceId = [LSUtil generateGUID];
        } else {
            self->m_traceId = traceId;
        }

        [self _addTags:tags];
    }
    return self;
}

- (void) dealloc {
}

- (LSTracer*) tracer {
    // The m_tracer pointer is immutable after initialization; no locking required.
    return m_tracer;
}

- (void) setOperationName:(NSString *)operationName {
    @synchronized(self) {
        m_operationName = operationName;
    }
}

- (void) setTag:(NSString *)key value:(NSString *)value {
    @synchronized(self) {
        [m_tags setObject:value forKey:key];
    }
}

- (void)logEvent:(NSString*)eventName {
    [self log:eventName timestamp:[NSDate date] payload:nil];
}

- (void)logEvent:(NSString*)eventName payload:(NSObject*)payload {
    [self log:eventName timestamp:[NSDate date] payload:payload];
}

- (void)log:(NSString*)eventName
  timestamp:(NSDate*)timestamp
    payload:(NSObject*)payload {

    // No locking is requied as all the member variables used below are immutable
    // after initialization:
    // - m_tracer
    // - m_spanId

    if (![m_tracer enabled]) {
        return;
    }

    NSString* payloadJSON = [LSUtil objectToJSONString:payload
                                             maxLength:[m_tracer maxPayloadJSONLength]];
    RLLogRecord* logRecord = [[RLLogRecord alloc]
                              initWithTimestamp_micros:[timestamp toMicros]
                              runtime_guid:[m_tracer runtimeGuid]
                              span_guid:[LSUtil hexGUID:m_spanId]
                              stable_name:eventName
                              message:nil
                              level:@"I"
                              thread_id:(int64_t)[NSThread currentThread]
                              filename:nil
                              line_number:0
                              stack_frames:nil
                              payload_json:payloadJSON
                              error_flag:false];

    [m_tracer _appendLogRecord:logRecord];
}

//
// NOTE: logError is a LightStep-specific method
//
- (void)logError:(NSString*)message error:(NSObject*)errorOrException {
    // No locking is required as all the member variables used below are immutable
    // after initialization:
    // - m_tracer
    // - m_spanId

    if (![m_tracer enabled]) {
        return;
    }

    [self setTag:@"error" value:@"true"];

    NSObject* payload;
    if ([errorOrException isKindOfClass:[NSException class]]) {
        NSException* exception = (NSException*)errorOrException;
        payload = @{@"name":exception.name ?: [NSNull null],
                    @"reason":exception.reason ?: [NSNull null],
                    @"userInfo":exception.userInfo ?: [NSNull null],
                    @"stack":exception.callStackSymbols ?: [NSNull null]};
    } else if ([errorOrException isKindOfClass:[NSError class]]) {
        NSError* error = (NSError*)errorOrException;
        payload = @{@"description":error.localizedDescription,
                    @"userInfo":error.userInfo ?: [NSNull null]};
    } else {
        payload = errorOrException;
    }

    NSString* payloadJSON = [LSUtil objectToJSONString:payload
                                             maxLength:[m_tracer maxPayloadJSONLength]];
    RLLogRecord* logRecord = [[RLLogRecord alloc]
                              initWithTimestamp_micros:[[NSDate date] toMicros]
                              runtime_guid:[m_tracer runtimeGuid]
                              span_guid:[LSUtil hexGUID:m_spanId]
                              stable_name:nil
                              message:message
                              level:@"E"
                              thread_id:(int64_t)[NSThread currentThread]
                              filename:nil
                              line_number:0
                              stack_frames:nil
                              payload_json:payloadJSON
                              error_flag:true];

    [m_tracer _appendLogRecord:logRecord];
}

- (void)setBaggageItem:(NSString*)key value:(NSString*)value {
    // TODO: need to check the key/value constraints
    @synchronized(self) {
        [m_baggage setObject:value forKey:key];
    }
}

- (NSString*)getBaggageItem:(NSString*)key {
    @synchronized(self) {
        id obj = [m_baggage objectForKey:key];
        return (NSString*)obj;
    }
}

- (void) finish {
    [self finishWithTime:[NSDate date]];
}

- (void) finishWithTime:(NSDate *)finishTime {
    if (finishTime == nil) {
        finishTime = [NSDate date];
    }

    RLSpanRecord* record;
    @synchronized(self) {
        NSMutableArray* tagArray;
        if (m_tags.count > 0) {
            tagArray = [[NSMutableArray alloc] initWithCapacity:m_tags.count];
            for (NSString* key in m_tags ) {
                RLKeyValue* pair = [[RLKeyValue alloc] initWithKey:key Value:[m_tags[key] description]];
                [tagArray addObject:pair];
            }
        }

        record = [[RLSpanRecord alloc] initWithSpan_guid:[LSUtil hexGUID:m_spanId]
                                              trace_guid:[LSUtil hexGUID:m_traceId]
                                            runtime_guid:m_tracer.runtimeGuid
                                               span_name:m_operationName
                                                join_ids:nil
                                           oldest_micros:[m_startTime toMicros]
                                         youngest_micros:[finishTime toMicros]
                                              attributes:tagArray
                                              error_flag:m_errorFlag
                                             log_records:nil];
    }
    [m_tracer _appendSpanRecord:record];
}

- (NSString*)traceGUID {
    return [LSUtil hexGUID:m_traceId];
}

- (void)setSpanId:(UInt64)spanId {
    self->m_spanId = spanId;
}

- (UInt64)spanId {
    return self->m_spanId;
}

- (void)setTraceId:(UInt64)traceId {
    self->m_traceId = traceId;
}

- (UInt64)traceId {
    return self->m_traceId;
}

- (void)_addTags:(NSDictionary*)tags {
    if (tags == nil) {
        return;
    }
    @synchronized(self) {
        [m_tags addEntriesFromDictionary:tags];
    }
}

- (NSString*)_getTag:(NSString*)key {
    @synchronized (self) {
        return (NSString*)[m_tags objectForKey:key];
    }
}

- (NSString*) hexTraceId {
    return [LSUtil hexGUID:self.traceId];
}

- (NSString*) hexSpanId {
    return [LSUtil hexGUID:self.spanId];
}

- (NSURL*)_generateTraceURL {
    int64_t now = [[NSDate date] toMicros];
    NSString* fmt = @"https://app.lightstep.com/%@/trace?span_guid=%@&at_micros=%@";
    NSString* accessToken = [[m_tracer accessToken] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString* guid = [[LSUtil hexGUID:m_spanId] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString* urlStr = [NSString stringWithFormat:fmt, accessToken, guid, @(now)];
    return [NSURL URLWithString:urlStr];
}

- (LSSpan*)_startChildSpan:(NSString*)operationName
                      tags:(NSDictionary*)tags
                 startTime:(NSDate*)startTime {

    return [[LSSpan alloc] initWithTracer:m_tracer
                            operationName:operationName
                                   parent:nil
                                     tags:tags
                                startTime:startTime];
}

@end
