#import "LSSpan.h"
#import "LSSpanContext.h"
#import "LSTracer.h"
#import "LSUtil.h"

#import "Collector.pbobjc.h"

#pragma mark - LSSpan

@implementation LSSpan {
    LSTracer* m_tracer;
    LSSpanContext* m_ctx;
    LSSpanContext* m_parent;
    NSString* m_operationName;
    NSDate* m_startTime;
    NSMutableArray<LSPBLog*>* m_logs;
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

    // No locking is requied as all the member variables used below are immutable
    // after initialization.

    if (![m_tracer enabled]) {
        return;
    }

    NSString* payloadJSON = [LSUtil objectToJSONString:payload
                                             maxLength:[m_tracer maxPayloadJSONLength]];
    LSPBLog* logRecord = [[LSPBLog alloc] init];
    logRecord.timestamp = [LSUtil protoTimestampFromDate:timestamp];
    NSMutableArray<LSPBKeyValue*>* logKeyValues = [NSMutableArray<LSPBKeyValue*> array];
    {
        LSPBKeyValue* val = [[LSPBKeyValue alloc] init];
        val.key = @"event";
        val.stringValue = eventName;
        [logKeyValues addObject:val];
    }
    if (payloadJSON != nil) {
        LSPBKeyValue* val = [[LSPBKeyValue alloc] init];
        val.key = @"payload_json";
        val.stringValue = payloadJSON;
        [logKeyValues addObject:val];
    }
    logRecord.keyvaluesArray = logKeyValues;
    [self _appendLog:logRecord];
}

- (void)_appendLog:(LSPBLog*)log {
    @synchronized(self) {
        if (m_logs == nil) {
            m_logs = [NSMutableArray<LSPBLog*> array];
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

    LSPBSpan* record;
    @synchronized(self) {
        record = [self _toProto:finishTime];
    }
    [m_tracer _appendSpanRecord:record];
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
 * Generate a protocol message representation. Return value must not be modified.
 */
- (LSPBSpan*)_toProto:(NSDate*)finishTime {
    LSPBSpan* record = [[LSPBSpan alloc] init];
    NSMutableArray* tagsArray;
    if (m_tags.count > 0) {
        tagsArray = [[NSMutableArray<LSPBKeyValue*> alloc] initWithCapacity:m_tags.count];
        for (NSString* key in m_tags ) {
            LSPBKeyValue* pair = [[LSPBKeyValue alloc] init];
            pair.key = key;
            NSObject* val = m_tags[key];
            if ([val isKindOfClass:[NSNumber class]]) {
                // NOTE: we cannot distinguish between int and boolean tag values 
                pair.intValue = ((NSNumber*)val).longLongValue;
            } else if ([val isKindOfClass:[NSString class]]) {
                pair.stringValue = (NSString*)val;
            } else {
                // Fallback for unexpected value types
                pair.stringValue = [val description];
            }
            [tagsArray addObject:pair];
        }
    }
    
    record.operationName = m_operationName;
    record.spanContext = [m_ctx toProto];
    LSPBReference* parent = nil;
    if (m_parent) {
        parent = [[LSPBReference alloc] init];
        parent.relationship = LSPBReference_Relationship_ChildOf;
        parent.spanContext = [m_parent toProto];
        [record.referencesArray addObject:parent];
    }
    record.startTimestamp = [LSUtil protoTimestampFromDate:m_startTime];
    record.durationMicros = [finishTime toMicros] - [m_startTime toMicros];
    if (tagsArray != nil) {
        record.tagsArray = tagsArray;
    }
    record.logsArray = m_logs;
    return record;
}

- (NSDate*)_startTime {
    return m_startTime;
}

@end
