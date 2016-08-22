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

// The LSSpanContext instance takes ownership over `baggage`.
- (instancetype)initWithTraceId:(UInt64)traceId
                         spanId:(UInt64)spanId
                        baggage:(NSMutableDictionary*)baggage;

/**
 * An iterator for OTSpanContext baggage.
 *
 * If the callback returns false, iteration stops and forEachBaggageItem:
 * returns early.
 */
- (void)forEachBaggageItem:(BOOL (^) (NSString* key, NSString* value))callback;

/**
 * The LightStep Span's probabilistically unique trace id.
 */
@property (nonatomic) UInt64 traceId;

/**
 * The LightStep Span's probabilistically unique (span) id.
 */
@property (nonatomic) UInt64 spanId;

/**
 * The trace id as a hexadecimal string.
 */
- (NSString*)hexTraceId;

/**
 * The span id as a hexadecimal string.
 */
- (NSString*)hexSpanId;

@end
