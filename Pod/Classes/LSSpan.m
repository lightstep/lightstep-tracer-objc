#import "LSSpan.h"
#import "LSSpanContext.h"
#import "LSTracer.h"
#import "LSUtil.h"

#import "Collector.pbobjc.h"

#pragma mark - LSSpan

@interface LSLog : NSObject

@property (nonatomic, readonly) NSDate* timestamp;
@property (nonatomic, readonly) NSDictionary<NSString*, NSObject*>* fields;

- (instancetype) initWithTimestamp:(NSDate*)timestamp
                            fields:(NSDictionary<NSString*, NSObject*>*)fields;

- (LSPBLog*) toProto;

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

- (LSPBLog*) toProto {
    LSPBLog* logRecord = [[LSPBLog alloc] init];
    logRecord.timestamp = [LSUtil protoTimestampFromDate:self.timestamp];
    NSMutableArray<LSPBKeyValue*>* logKeyValues = [NSMutableArray<LSPBKeyValue*> arrayWithCapacity:self.fields.count];
    for (NSString* key in self.fields) {
        NSObject* val = [self.fields objectForKey:key];
        if (val == nil) {
            continue;
        }
        LSPBKeyValue* protoKV = [[LSPBKeyValue alloc] init];
        protoKV.key = key;
        if ([val isKindOfClass:[NSString class]]) {
            protoKV.stringValue = (NSString*)val;
        } else if ([val isKindOfClass:[NSNumber class]]) {
            NSNumber *numericVal = (NSNumber*)val;
            if (CFNumberIsFloatType((CFNumberRef)numericVal)) {
                protoKV.doubleValue = [numericVal doubleValue];
            } else {
                protoKV.intValue = [numericVal longLongValue];
            }
        } else {
            protoKV.stringValue = [val description];
        }
        [logKeyValues addObject:protoKV];
    }
    logRecord.keyvaluesArray = logKeyValues;
    return logRecord;
}

- (NSDictionary*) toJSON:(int)maxPayloadJSONLength {
    /*
     TimestampMicros *int64   `thrift:"timestamp_micros,1" json:"timestamp_micros"`
     RuntimeGuid     *string  `thrift:"runtime_guid,2" json:"runtime_guid"`
     SpanGuid        *string  `thrift:"span_guid,3" json:"span_guid"`
     StableName      *string  `thrift:"stable_name,4" json:"stable_name"`
     Message         *string  `thrift:"message,5" json:"message"`
     Level           *string  `thrift:"level,6" json:"level"`
     ThreadId        *int64   `thrift:"thread_id,7" json:"thread_id"`
     Filename        *string  `thrift:"filename,8" json:"filename"`
     LineNumber      *int64   `thrift:"line_number,9" json:"line_number"`
     StackFrames     []string `thrift:"stack_frames,10" json:"stack_frames"`
     PayloadJson     *string  `thrift:"payload_json,11" json:"payload_json"`
     ErrorFlag       *bool    `thrift:"error_flag,12" json:"error_flag"`
     */
    NSMutableDictionary *inputFields = self.fields;
    NSMutableDictionary<NSString*, NSObject*>* outputFields = [NSMutableDictionary<NSString*, NSObject*> dictionary];
    NSObject* eventVal;
    if (eventVal = [inputFields objectForKey:@"event"]) {
        outputFields[@"stable_name"] = eventVal;
        // Copy on write... (removing the event key from the input dict)
        inputFields = [NSMutableDictionary dictionaryWithDictionary:inputFields];
        [inputFields removeObjectForKey:@"event"];
    }
    NSObject* payloadVal;
    if (payloadVal = [inputFields objectForKey:@"payload_json"]) {
        outputFields[@"payload_json"] = payloadVal;
    } else {
        outputFields[@"payload_json"] = [LSUtil objectToJSONString:inputFields
                                                         maxLength:maxPayloadJSONLength];
    }
    outputFields[@"timestamp_micros"] = @([self.timestamp toMicros]);
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
    /*
     type SpanRecord struct {
     SpanGuid       *string        `thrift:"span_guid,1" json:"span_guid"`
     RuntimeGuid    *string        `thrift:"runtime_guid,2" json:"runtime_guid"`
     SpanName       *string        `thrift:"span_name,3" json:"span_name"`
     JoinIds        []*TraceJoinId `thrift:"join_ids,4" json:"join_ids"`
     OldestMicros   *int64         `thrift:"oldest_micros,5" json:"oldest_micros"`
     YoungestMicros *int64         `thrift:"youngest_micros,6" json:"youngest_micros"`
     // unused field # 7
     Attributes []*KeyValue  `thrift:"attributes,8" json:"attributes"`
     ErrorFlag  *bool        `thrift:"error_flag,9" json:"error_flag"`
     LogRecords []*LogRecord `thrift:"log_records,10" json:"log_records"`
     TraceGuid  *string      `thrift:"trace_guid,11" json:"trace_guid"`
     }
     */
    NSMutableArray<LSPBLog*>* logs = [NSMutableArray arrayWithCapacity:m_logs.count];
    for (LSLog *l in m_logs) {
        [logs addObject:[l toJSON:m_tracer.maxPayloadJSONLength]];
    }
    return @{
             @"trace_guid": m_ctx.hexTraceId,
             @"span_guid": m_ctx.hexSpanId,
             @"span_name": m_operationName,
             @"oldest_micros": @([m_startTime toMicros]),
             @"youngest_micros": @([finishTime toMicros]),
             @"attributes": [LSUtil keyValueArrayFromDictionary:m_tags],
             @"log_records": logs,
             };
}

/**
 * Generate a protocol message representation. Return value must not be modified.
 */
- (LSPBSpan*)_toProto:(NSDate*)finishTime {
    LSPBSpan* record = [[LSPBSpan alloc] init];
    NSMutableArray* tagsArray;
    if (m_tags.count > 0) {
        tagsArray = [[NSMutableArray<LSPBKeyValue*> alloc] initWithCapacity:m_tags.count];
        for (NSString* key in m_tags) {
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
