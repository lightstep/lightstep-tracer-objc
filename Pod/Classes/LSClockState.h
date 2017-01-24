#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@protocol LSTimeProvider
- (NSDate *)currentTime;
- (SInt64)offsetInMicroseconds;
@end

/// A straight port/copy of the `rl-cruntime-common` ClockState javascript prototype.
@interface LSClockState : NSObject<LSTimeProvider>

+ (LSClockState *)sharedClock;

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
