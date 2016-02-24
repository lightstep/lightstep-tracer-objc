//
//  RLClockState.h
//

#import <Foundation/Foundation.h>

typedef int64_t micros_t;

@class RLClient;

/// A straight port/copy of the `rl-cruntime-common` ClockState javascript prototype.
@interface RLClockState : NSObject

// A helper that returns the local timestamp in microseconds (since the unix epoch).
+ (micros_t) nowMicros;

- (id) initWithRLClient:(RLClient*)rlClient;

/// Provide information about a fresh clock-skew datapoint.
///
/// originMicros represents the local time of transmission.
///
/// receiveMicros represents the time the remote server received the synchronization message (according to the server's clock).
///
/// receiveMicros represents the time the remote server sent the synchronization reply (according to the server's clock).
///
/// destinatioMicros represents the local time of receipt for the synchronization reply.
///
/// All timestamps are in microseconds.
- (void) addSampleWithOriginMicros:(micros_t)originMicros receiveMicros:(micros_t)receiveMicros transmitMicros:(micros_t)transmitMicros destinationMicros:(micros_t)destinationMicros;

/// Force an update of the internal clock-skew machinery.
- (void) update;

/// Return the most-recently-computed (via `update`) offset between server and client in microseconds. This should be *added* to any local timestamps before sending to the server.
- (micros_t) offsetMicros;

@end
