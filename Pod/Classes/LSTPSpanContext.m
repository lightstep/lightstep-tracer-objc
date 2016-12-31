//
//  LSTPSpanContext.m
//  LightStepTestUI
//
//  Created by Ben Sigelman on 7/21/16.
//  Copyright © 2016 LightStep. All rights reserved.
//

#import "LSTPSpanContext.h"
#import "LSTPUtil.h"

@implementation LSTPSpanContext {
    NSDictionary* m_baggage;
}

- (instancetype)initWithTraceId:(UInt64)traceId
                         spanId:(UInt64)spanId
                        baggage:(nullable NSDictionary*)baggage {
    if (self = [super init]) {
        self.traceId = traceId;
        self.spanId = spanId;
        if (baggage == nil) {
            self->m_baggage = [NSDictionary dictionary];
        } else {
            self->m_baggage = baggage;
        }
    }
    return self;
}

- (LSTPSpanContext*)withBaggageItem:(NSString*)key value:(NSString*)value {
    NSMutableDictionary* baggageCopy = [self->m_baggage mutableCopy];
    [baggageCopy setObject:value forKey:key];
    return [[LSTPSpanContext alloc] initWithTraceId:self.traceId spanId:self.spanId baggage:baggageCopy];
}


- (NSString*)getBaggageItem:(NSString*)key {
    return (NSString*)[m_baggage objectForKey:key];
}

- (void)forEachBaggageItem:(BOOL (^) (NSString* key, NSString* value))callback {
    for (NSString* key in m_baggage) {
        if (!callback(key, [m_baggage objectForKey:key])) {
            return;
        }
    }
}

- (NSString*)hexTraceId {
    return [LSTPUtil hexGUID:self.traceId];
}

- (NSString*)hexSpanId {
    return [LSTPUtil hexGUID:self.spanId];
}

- (NSDictionary*)_baggage {
    return m_baggage;
}

@end
