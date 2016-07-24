#import <Foundation/Foundation.h>

#import "OTSpan.h"

@class LSSpanContext;
@class LSTracer;

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
- (void)logEvent:(NSString*)eventName payload:(NSObject*)payload;
- (void)log:(NSString*)eventName
  timestamp:(NSDate*)timestamp
    payload:(NSObject*)payload;

- (void) finish;
- (void) finishWithTime:(NSDate*)finishTime;

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
 * LightStep specific method for logging an error (or exception).
 */
- (void)logError:(NSString*)message error:(NSObject*)errorOrException;

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

@end
