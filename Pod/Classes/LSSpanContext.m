//
//  LSSpanContext.m
//  LightStepTestUI
//
//  Created by Ben Sigelman on 7/21/16.
//  Copyright © 2016 LightStep. All rights reserved.
//

#import "LSSpanContext.h"

#import "LSUtil.h"
#import "Collector.pbobjc.h"

@implementation LSSpanContext {
    NSMutableDictionary* m_baggage;
}

- (instancetype)initWithTraceId:(UInt64)traceId
                         spanId:(UInt64)spanId
                        baggage:(NSMutableDictionary*)baggage {
    if (self = [super init]) {
        self.traceId = traceId;
        self.spanId = spanId;
        if (baggage == nil) {
            self->m_baggage = [NSMutableDictionary dictionary];
        } else {
            self->m_baggage = baggage;
        }
    }
    return self;
}

- (void)setBaggageItem:(NSString*)key value:(NSString*)value {
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

- (void)forEachBaggageItem:(BOOL (^) (NSString* key, NSString* value))callback {
    @synchronized(self) {
        for (NSString* key in m_baggage) {
            if (!callback(key, [m_baggage objectForKey:key])) {
                return;
            }
        }
    }
}

- (LTSSpanContext*)toProto {
    LTSSpanContext* rval = [[LTSSpanContext alloc] init];
    rval.traceId = self.traceId;
    rval.spanId = self.spanId;
    return rval;
}

- (NSString*)hexTraceId {
    return [LSUtil hexGUID:self.traceId];
}

- (NSString*)hexSpanId {
    return [LSUtil hexGUID:self.spanId];
}

@end
