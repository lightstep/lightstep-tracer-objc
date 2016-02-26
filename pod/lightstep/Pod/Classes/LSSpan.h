#import <Foundation/Foundation.h>

#import "crouton.h"

@class LSTracer;

/**
 * An `LSSpan` represents a logical unit of work done by the service. One or
 * more spans – presumably from different processes – are assembled into traces.
 */
@interface LSSpan : NSObject

#pragma mark - OpenTracing API

/**
 * The Tracer instance that created this span.
 */
- (LSTracer*)tracer;

/**
 * Set operation name
 */
- (void)setOperationName:(NSString*)operationName;

/**
 * Adds a single tag to the span.
 */
- (void)setTag:(NSString*)key value:(NSString*)value;

/**
 * Log a timestamped event.
 */
- (void)logEvent:(NSString*)eventName;

/**
 * Log a timestamped event along with an arbitrary payload of data.
 */
- (void)logEvent:(NSString*)eventName payload:(NSObject*)payload;

/**
 * Create a log record for given event with a manually specified timestamp
 * and an optional payload.
 */
- (void)log:(NSString*)eventName
  timestamp:(NSDate*)timestamp
    payload:(NSObject*)payload;

/**
 * TODO: docs
 */
- (void)setBaggageItem:(NSString*)key value:(NSString*)value;

/**
 * TODO: docs
 */
- (NSString*)getBaggageItem:(NSString*)key;

/**
 * Mark the end time and record this span.
 */
- (void) finish;

/**
 * Record this span with the explicitly specified finish time.
 */
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
                         parent:(LSSpan*)parent
                           tags:(NSDictionary*)tags
                      startTime:(NSDate*)startTime;

/**
 * Add a set of tags from the given dictionary. Existing key-value pairs will
 * be overwritten by any new tags.
 */
- (void)_addTags:(NSDictionary*)tags;

/**
 * Create a new span that is a child of this span, optionally with the given
 * tags and start time.
 */
- (LSSpan*)_startChildSpan:(NSString*)operationName
                      tags:(NSDictionary*)tags
                 startTime:(NSDate*)startTime;


@end
