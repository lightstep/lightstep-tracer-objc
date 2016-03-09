#import <Foundation/Foundation.h>

typedef int64_t micros_t;

@class LSTracer;

/** 
 * A straight port/copy of the `rl-cruntime-common` ClockState javascript 
 * prototype.
 */
@interface LSClockState : NSObject

// A helper that returns the local timestamp in microseconds (since the unix epoch).
+ (micros_t) nowMicros;

- (id) initWithLSTracer:(LSTracer*)tracer;

/** 
 * Provide information about a fresh clock-skew datapoint.
 *
 * @param originMicros represents the local time of transmission.
 *
 * @param receiveMicros represents the time the remote server received the
 * synchronization message (according to the server's clock).
 *
 * @param receiveMicros represents the time the remote server sent the synchronization
 * reply (according to the server's clock).
 *
 * @param destinatioMicros represents the local time of receipt for the synchronization reply.
 *
 * All timestamps are in microseconds.
 */
- (void) addSampleWithOriginMicros:(micros_t)originMicros
                     receiveMicros:(micros_t)receiveMicros
                    transmitMicros:(micros_t)transmitMicros
                 destinationMicros:(micros_t)destinationMicros;

/** 
 * Force an update of the internal clock-skew machinery.
 */
- (void) update;

/** 
 * Return the most-recently-computed (via `update`) offset between server and 
 * client in microseconds. This should be *added* to any local timestamps before
 * sending to the server.
 */
- (micros_t) offsetMicros;

@end
