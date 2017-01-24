#import "LSSpan.h"
#import "LSSpanContext.h"
#import "LSTracer.h"
#import "LSClockState.h"
#import "LSUtil.h"

#pragma mark - LSLog

@interface LSLog : NSObject

@property(nonatomic, readonly) NSDate *timestamp;
@property(nonatomic, readonly) NSDictionary<NSString *, NSObject *> *fields;

- (instancetype)initWithTimestamp:(NSDate *)timestamp fields:(NSDictionary<NSString *, NSObject *> *)fields;

@end

@implementation LSLog

- (instancetype)initWithTimestamp:(NSDate *)timestamp fields:(NSDictionary<NSString *, NSObject *> *)fields {
    if (self = [super init]) {
        _timestamp = timestamp;
        _fields = [NSDictionary dictionaryWithDictionary:fields];
    }
    return self;
}

- (NSDictionary *)toJSONWithMaxPayloadLength:(NSUInteger)maxPayloadJSONLength {
    NSMutableDictionary<NSString *, NSObject *> *outputFields = @{}.mutableCopy;
    outputFields[@"timestamp_micros"] = @([self.timestamp toMicros]);
    if (self.fields.count > 0) {
        outputFields[@"fields"] = [LSUtil keyValueArrayFromDictionary:self.fields];
    }
    return outputFields;
}

@end

#pragma mark - LSSpan

@interface LSSpan ()
@property(nonatomic, strong) LSSpanContext *parent;
@property(atomic, strong) NSString *operationName;
@property(atomic, strong) LSSpanContext *context;
@property(nonatomic, strong) NSMutableArray<LSLog *> *logs;
@property(atomic, strong, readonly) NSMutableDictionary<NSString *, NSString *> *mutableTags;
@end

@implementation LSSpan

- (instancetype)initWithTracer:(LSTracer *)client {
    return [self initWithTracer:client operationName:@"" parent:nil tags:nil startTime:nil];
}

- (instancetype)initWithTracer:(LSTracer *)tracer
                 operationName:(NSString *)operationName
                        parent:(nullable LSSpanContext *)parent
                          tags:(nullable NSDictionary *)tags
                     startTime:(nullable NSDate *)startTime {
    if (self = [super init]) {
        _tracer = tracer;
        _operationName = operationName;
        _startTime = startTime ?: [tracer.timeProvider currentTime];
        _logs = @[].mutableCopy;
        _mutableTags = @{}.mutableCopy;
        _parent = parent;

        UInt64 traceId = parent.traceId ?: [LSUtil generateGUID];
        UInt64 spanId = [LSUtil generateGUID];
        _context = [[LSSpanContext alloc] initWithTraceId:traceId spanId:spanId baggage:parent.baggage];

        [self addTags:tags];
    }
    return self;
}

- (NSDictionary<NSString *, NSString *> *)tags {
    return [self.mutableTags copy];
}

- (void)setTag:(NSString *)key value:(NSString *)value {
    [self.mutableTags setObject:value forKey:key];
}

- (void)logEvent:(NSString *)eventName {
    [self log:eventName timestamp:[self.tracer.timeProvider currentTime] payload:nil];
}

- (void)logEvent:(NSString *)eventName payload:(NSObject *)payload {
    [self log:eventName timestamp:[self.tracer.timeProvider currentTime] payload:payload];
}

- (void)log:(NSString *)eventName timestamp:(NSDate *)timestamp payload:(NSObject *)payload {
    // No locking is required as all the member variables used below are immutable
    // after initialization.

    if (!self.tracer.enabled) {
        return;
    }

    NSMutableDictionary<NSString *, NSObject *> *fields = [NSMutableDictionary<NSString *, NSObject *> dictionary];
    if (eventName != nil) {
        fields[@"event"] = eventName;
    }
    if (payload != nil) {
        NSString *payloadJSON = [LSUtil objectToJSONString:payload maxLength:[self.tracer maxPayloadJSONLength]];
        fields[@"payload_json"] = payloadJSON;
    }
    [self _appendLog:[[LSLog alloc] initWithTimestamp:timestamp fields:fields]];
}

- (void)log:(NSDictionary<NSString *, NSObject *> *)fields {
    [self log:fields timestamp:[self.tracer.timeProvider currentTime]];
}

- (void)log:(NSDictionary<NSString *, NSObject *> *)fields timestamp:(nullable NSDate *)timestamp {
    // No locking is required as all the member variables used below are immutable
    // after initialization.
    if (!self.tracer.enabled) {
        return;
    }
    [self _appendLog:[[LSLog alloc] initWithTimestamp:timestamp fields:fields]];
}

- (void)_appendLog:(LSLog *)log {
    [self.logs addObject:log];
}

- (void)finish {
    [self finishWithTime:[NSDate date]];
}

- (void)finishWithTime:(NSDate *)finishTime {
    if (finishTime == nil) {
        finishTime = [NSDate date];
    }

    NSDictionary *spanJSON;
    @synchronized(self) {
        spanJSON = [self _toJSONWithFinishTime:finishTime];
    }
    [self.tracer _appendSpanJSON:spanJSON];
}

- (id<OTSpan>)setBaggageItem:(NSString *)key value:(NSString *)value {
    // TODO: change selector in OTSpan.h to setBaggageItem:forKey:
    self.context = [self.context withBaggageItem:key value:value];
    return self;
}

- (NSString *)getBaggageItem:(NSString *)key {
    // TODO: rename selector in OTSpan.h to baggageItemForKey:
    return [self.context baggageItemForKey:key];
}

/// Add a set of tags from the given dictionary. Existing key-value pairs will be overwritten by any new tags.
- (void)addTags:(NSDictionary *)tags {
    if (tags == nil) {
        return;
    }
    [self.mutableTags addEntriesFromDictionary:tags];
}

- (NSString *)tagForKey:(NSString *)key {
    return (NSString *)[self.mutableTags objectForKey:key];
}

- (NSURL *)traceURL {
    int64_t now = [[NSDate date] toMicros];
    NSString *fmt = @"https://app.lightstep.com/%@/trace?span_guid=%@&at_micros=%@";
    NSString *accessToken = [[self.tracer accessToken] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *guid =
        [[LSUtil hexGUID:self.context.spanId] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *urlStr = [NSString stringWithFormat:fmt, accessToken, guid, @(now)];
    return [NSURL URLWithString:urlStr];
}

/**
 * Generate a JSON-ready NSDictionary representation. Return value must not be
 * modified.
 */
- (NSDictionary *)_toJSONWithFinishTime:(NSDate *)finishTime {
    NSMutableArray<NSDictionary *> *logs = [NSMutableArray arrayWithCapacity:self.logs.count];
    for (LSLog *l in self.logs) {
        [logs addObject:[l toJSONWithMaxPayloadLength:self.tracer.maxPayloadJSONLength]];
    }

    NSMutableArray *attributes = [LSUtil keyValueArrayFromDictionary:self.mutableTags];
    if (self.parent != nil) {
        [attributes addObject:@{ @"Key": @"parent_span_guid", @"Value": self.parent.hexSpanId }];
    }

    // return value spec:
    // https://github.com/lightstep/lightstep-tracer-go/blob/40cbd138e6901f0dafdd0cccabb6fc7c5a716efb/lightstep_thrift/ttypes.go#L1247
    return @{
        @"trace_guid": self.context.hexTraceId,
        @"span_guid": self.context.hexSpanId,
        @"span_name": self.operationName,
        @"oldest_micros": @([self.startTime toMicros]),
        @"youngest_micros": @([finishTime toMicros]),
        @"attributes": attributes,
        @"log_records": logs,
    };
}

@end
