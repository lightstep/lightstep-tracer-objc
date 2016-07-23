//
//  LSSpanContext.h
//  LightStepTestUI
//
//  Created by Ben Sigelman on 7/21/16.
//  Copyright © 2016 LightStep. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "OTSpanContext.h"

@interface LSSpanContext : NSObject<OTSpanContext>

#pragma mark - OpenTracing API

- (void)setBaggageItem:(NSString*)key value:(NSString*)value;
- (NSString*)getBaggageItem:(NSString*)key;

#pragma mark - LightStep API

@property (strong, nonatomic) UInt64 traceId;
@property (strong, nonatomic) UInt64 spanId;

- (instancetype)initWithTraceId:(UInt64)traceId spanId:(UInt64)spanId;

@end
