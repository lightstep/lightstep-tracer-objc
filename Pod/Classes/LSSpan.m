#import "LSSpan.h"
#import "LSSpanContext.h"
#import "LSTracer.h"
#import "LSUtil.h"

#pragma mark - LSSpan

@interface LSLog : NSObject

@property (nonatomic, readonly) NSDate* timestamp;
@property (nonatomic, readonly) NSDictionary<NSString*, NSObject*>* fields;

- (instancetype) initWithTimestamp:(NSDate*)timestamp
                            fields:(NSDictionary<NSString*, NSObject*>*)fields;

@end

@implementation LSLog

- (instancetype) initWithTimestamp:(NSDate*)timestamp
                            fields:(NSDictionary<NSString*, NSObject*>*)fields {
    if (self = [super init]) {
        self->_timestamp = timestamp;
        self->_fields = [NSDictionary dictionaryWithDictionary:fields];
    }
    return self;
}

- (NSDictionary*) toJSON:(int)maxPayloadJSONLength {
    // outputFields spec: https://github.com/lightstep/lightstep-tracer-go/blob/3699758ec6e003d09bb521274c0cc01a798e45d7/lightstep_thrift/ttypes.go#L513
    NSMutableDictionary<NSString*, NSObject*>* outputFields = [NSMutableDictionary<NSString*, NSObject*> dictionary];
    outputFields[@"timestamp_micros"] = @([self.timestamp toMicros]);
    if (self.fields.count > 0) {
        outputFields[@"fields"] = [LSUtil keyValueArrayFromDictionary:self.fields];
    }
    return outputFields;
}

@end

@implementation LSSpan {
    LSTracer* m_tracer;
    LSSpanContext* m_ctx;
    LSSpanContext* m_parent;
    NSString* m_operationName;
    NSDate* m_startTime;
    NSMutableArray<LSLog*>* m_logs;
    NSMutableDictionary* m_tags;
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
                         parent:(nullable LSSpanContext*)parent
                           tags:(nullable NSDictionary*)tags
                      startTime:(nullable NSDate*)startTime {
    if (self = [super init]) {
        self->m_tracer = tracer;
        self->m_operationName = operationName;
        self->m_startTime = startTime;
        self->m_tags = [NSMutableDictionary dictionary];
        self->m_logs = nil;

        if (startTime == nil) {
            m_startTime = [NSDate date];
        }
        UInt64 traceId = (parent == nil) ? [LSUtil generateGUID] : parent.traceId;
        UInt64 spanId = [LSUtil generateGUID];
        if (parent != nil) {
            self->m_parent = parent;
        }
        self->m_ctx = [[LSSpanContext alloc] initWithTraceId:traceId spanId:spanId baggage:parent._baggage];

        [self _addTags:tags];
    }
    return self;
}

- (id<OTSpanContext>) context {
    // The m_ctx pointer is immutable after initialization; no locking required.
    return m_ctx;
}

- (id<OTTracer>) tracer {
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

    // No locking is required as all the member variables used below are immutable
    // after initialization.

    if (![m_tracer enabled]) {
        return;
    }

    NSMutableDictionary<NSString*, NSObject*>* fields = [NSMutableDictionary<NSString*, NSObject*> dictionary];
    if (eventName != nil) {
        fields[@"event"] = eventName;
    }
    if (payload != nil) {
        NSString* payloadJSON = [LSUtil objectToJSONString:payload
                                                 maxLength:[m_tracer maxPayloadJSONLength]];
        fields[@"payload_json"] = payloadJSON;
    }
    [self _appendLog:[[LSLog alloc] initWithTimestamp:timestamp fields:fields]];
}

- (void)log:(NSDictionary<NSString*, NSObject*>*)fields {
    [self log:fields timestamp:[NSDate date]];
}

- (void)log:(NSDictionary<NSString*, NSObject*>*)fields timestamp:(nullable NSDate*)timestamp {
    // No locking is required as all the member variables used below are immutable
    // after initialization.
    if (![m_tracer enabled]) {
        return;
    }
    [self _appendLog:[[LSLog alloc] initWithTimestamp:timestamp fields:fields]];
}

- (void)_appendLog:(LSLog*)log {
    @synchronized(self) {
        if (m_logs == nil) {
            m_logs = [NSMutableArray<LSLog*> array];
        }
        [m_logs addObject:log];
    }
}

- (void) finish {
    [self finishWithTime:[NSDate date]];
}

- (void) finishWithTime:(NSDate *)finishTime {
    if (finishTime == nil) {
        finishTime = [NSDate date];
    }

    NSDictionary* spanJSON;
    @synchronized(self) {
        spanJSON = [self _toJSON:finishTime];
    }
    [m_tracer _appendSpanJSON:spanJSON];
}

- (id<OTSpan>)setBaggageItem:(NSString*)key value:(NSString*)value {
    @synchronized(self) {
        m_ctx = [m_ctx withBaggageItem:key value:value];
    }
    return self;
}

- (NSString*)getBaggageItem:(NSString*)key {
    @synchronized(self) {
        return [m_ctx getBaggageItem:key];
    }
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

- (NSURL*)_generateTraceURL {
    int64_t now = [[NSDate date] toMicros];
    NSString* fmt = @"https://app.lightstep.com/%@/trace?span_guid=%@&at_micros=%@";
    NSString* accessToken = [[m_tracer accessToken] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString* guid = [[LSUtil hexGUID:m_ctx.spanId] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString* urlStr = [NSString stringWithFormat:fmt, accessToken, guid, @(now)];
    return [NSURL URLWithString:urlStr];
}

/**
 * Generate a JSON-ready NSDictionary representation. Return value must not be modified.
 */
- (NSDictionary*)_toJSON:(NSDate*)finishTime {
    NSMutableArray<NSDictionary*>* logs = [NSMutableArray arrayWithCapacity:m_logs.count];
    for (LSLog *l in m_logs) {
        [logs addObject:[l toJSON:m_tracer.maxPayloadJSONLength]];
    }
    
    NSMutableArray* attributes = [LSUtil keyValueArrayFromDictionary:m_tags];
    if (m_parent != nil) {
        [attributes addObject:@{@"Key": @"parent_span_guid", @"Value": m_parent.hexSpanId}];
    }
    
    // return value spec: https://github.com/lightstep/lightstep-tracer-go/blob/40cbd138e6901f0dafdd0cccabb6fc7c5a716efb/lightstep_thrift/ttypes.go#L1247
    return @{
             @"trace_guid": m_ctx.hexTraceId,
             @"span_guid": m_ctx.hexSpanId,
             @"span_name": m_operationName,
             @"oldest_micros": @([m_startTime toMicros]),
             @"youngest_micros": @([finishTime toMicros]),
             @"attributes": attributes,
             @"log_records": logs,
             };
}

- (NSDate*)_startTime {
    return m_startTime;
}

@end
