#import <Foundation/Foundation.h>

#import "OTSpan.h"

NS_ASSUME_NONNULL_BEGIN

@class LSSpanContext;
@class LSTracer;
@class LSPBSpan;

/**
 * An `LSSpan` represents a logical unit of work done by the service. One or
 * more spans – presumably from different processes – are assembled into traces.
 *
 * The LSSpan class is thread-safe.
 */
@interface LSSpan : NSObject<OTSpan>

#pragma mark - OpenTracing API

- (id<OTSpanContext>)context;

- (id<OTTracer>)tracer;

- (void)setOperationName:(NSString*)operationName;

- (void)setTag:(NSString*)key value:(NSString*)value;

- (void)logEvent:(NSString*)eventName;
- (void)logEvent:(NSString*)eventName payload:(nullable NSObject*)payload;
- (void)log:(NSString*)eventName
  timestamp:(nullable NSDate*)timestamp
    payload:(nullable NSObject*)payload;

- (void) finish;
- (void) finishWithTime:(nullable NSDate*)finishTime;

- (id<OTSpan>)setBaggageItem:(NSString*)key value:(NSString*)value;
- (NSString*)getBaggageItem:(NSString*)key;

#pragma mark - LightStep extensions and internal methods

/**
 * Internal function.
 * 
 * Creates a new span associated with the given tracer.
 */
- (instancetype) initWithTracer:(LSTracer*)tracer;

/**
 * Internal function.
 *
 * Creates a new span associated with the given tracer and the other optional
 * parameters.
 */
- (instancetype) initWithTracer:(LSTracer*)tracer
                  operationName:(NSString*)operationName
                         parent:(LSSpanContext*)parent
                           tags:(NSDictionary*)tags
                      startTime:(NSDate*)startTime;

/**
 * 
 */
@property (nonatomic, strong) NSDictionary* tags;

/**
 * Add a set of tags from the given dictionary. Existing key-value pairs will
 * be overwritten by any new tags.
 */
- (void)_addTags:(NSDictionary*)tags;

/**
 * Get a particular tag.
 */
- (NSString*)_getTag:(NSString*)key;

/**
 * Generate a URL to the trace containing this span on LightStep.
 */
- (NSURL*)_generateTraceURL;


// For testing only
- (LSPBSpan*)_toProto:(NSDate*)finishTime;
@property (nonatomic, readonly) NSDate* _startTime;

@end

NS_ASSUME_NONNULL_END
