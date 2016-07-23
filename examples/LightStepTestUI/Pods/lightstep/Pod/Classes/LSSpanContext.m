//
//  LSSpanContext.m
//  LightStepTestUI
//
//  Created by Ben Sigelman on 7/21/16.
//  Copyright © 2016 LightStep. All rights reserved.
//

#import "LSSpanContext.h"

#import "LSUtil.h"

@implementation LSSpanContext {
    NSMutableDictionary* m_baggage;
}

- (instancetype)initWithTraceId:(UInt64)traceId spanId:(UInt64)spanId {
    if (self = [super init]) {
        self.traceId = traceId;
        self.spanId = spanId;
        self->m_baggage = [NSMutableDictionary dictionary];
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

- (NSString*)hexTraceId {
    return [LSUtil hexGUID:self.traceId];
}

- (NSString*)hexSpanId {
    return [LSUtil hexGUID:self.spanId];
}

@end
