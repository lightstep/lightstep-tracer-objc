//
//  LSSpanContext.h
//  LightStepTestUI
//
//  Created by Ben Sigelman on 7/21/16.
//  Copyright © 2016 LightStep. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <opentracing/OTSpanContext.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSSpanContext : NSObject<OTSpanContext>

#pragma mark - OpenTracing API

/// An iterator for OTSpanContext baggage.
///
/// If the callback returns false, iteration stops and forEachBaggageItem:
/// returns early.
- (void)forEachBaggageItem:(BOOL (^)(NSString *key, NSString *value))callback;

#pragma mark - LightStep API

- (instancetype)initWithTraceId:(UInt64)traceId spanId:(UInt64)spanId baggage:(nullable NSDictionary *)baggage;

/// Return a copy of this SpanContext with the given (potentially additional) baggage item.
- (LSSpanContext *)withBaggageItem:(NSString *)key value:(NSString *)value;

/// Return a specific baggage item.
- (NSString *)getBaggageItem:(NSString *)key;

/// The LightStep Span's probabilistically unique trace id.
@property(nonatomic) UInt64 traceId;

/// The LightStep Span's probabilistically unique (span) id.
@property(nonatomic) UInt64 spanId;

/// The trace id as a hexadecimal string.
- (NSString *)hexTraceId;

/// The span id as a hexadecimal string.
- (NSString *)hexSpanId;

#pragma mark - Internal

/// The baggage dictionary (for internal use only).
@property(nonatomic, readonly) NSDictionary *baggage;

@end

NS_ASSUME_NONNULL_END
