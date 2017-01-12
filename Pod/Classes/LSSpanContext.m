//
//  LSSpanContext.m
//  LightStepTestUI
//
//  Created by Ben Sigelman on 7/21/16.
//  Copyright © 2016 LightStep. All rights reserved.
//

#import "LSSpanContext.h"
#import "LSUtil.h"

@implementation LSSpanContext

- (instancetype)initWithTraceId:(UInt64)traceId spanId:(UInt64)spanId baggage:(nullable NSDictionary *)baggage {
    if (self = [super init]) {
        _traceId = traceId;
        _spanId = spanId;
        _baggage = baggage ?: @{};
    }
    return self;
}

- (LSSpanContext *)withBaggageItem:(NSString *)key value:(NSString *)value {
    NSMutableDictionary *baggageCopy = [self.baggage mutableCopy];
    [baggageCopy setObject:value forKey:key];
    return [[LSSpanContext alloc] initWithTraceId:self.traceId spanId:self.spanId baggage:baggageCopy];
}

- (NSString *)getBaggageItem:(NSString *)key {
    return (NSString *)[self.baggage objectForKey:key];
}

- (void)forEachBaggageItem:(BOOL (^)(NSString *key, NSString *value))callback {
    for (NSString *key in self.baggage) {
        if (!callback(key, [self.baggage objectForKey:key])) {
            return;
        }
    }
}

- (NSString *)hexTraceId {
    return [LSUtil hexGUID:self.traceId];
}

- (NSString *)hexSpanId {
    return [LSUtil hexGUID:self.spanId];
}

@end
