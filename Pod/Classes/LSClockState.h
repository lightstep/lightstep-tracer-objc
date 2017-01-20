#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

/// A straight port/copy of the `rl-cruntime-common` ClockState javascript prototype.
@interface LSClockState : NSObject

/// A helper that returns the local timestamp in microseconds (since the unix epoch).
+ (SInt64)nowMicros;

/// The most-recently-computed (via `update`) offset between server and client in microseconds.
/// This should be *added* to any local timestamps before sending to the server.
@property(nonatomic, readonly) SInt64 offsetMicros;

/// Provide information about a fresh clock-skew datapoint.
///
/// @param originMicros: represents the local time of transmission.
///
/// @param receiveMicros: represents the time the remote server received the synchronization message
///                       (according to the server's clock).
///
/// @param receiveMicros: represents the time the remote server sent the synchronization reply
///                       (according to the server's clock).
///
/// @param destinationMicros: represents the local time of receipt for the synchronization reply.
- (void)addSampleWithOriginMicros:(SInt64)originMicros
                    receiveMicros:(SInt64)receiveMicros
                   transmitMicros:(SInt64)transmitMicros
                destinationMicros:(SInt64)destinationMicros;

/// Force an update of the internal clock-skew machinery.
- (void)update;

@end
NS_ASSUME_NONNULL_END
