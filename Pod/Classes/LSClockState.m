#import "LSClockState.h"
#import "LSTracer.h"

static const int kMaxOffsetAge = 7;
static const UInt64 kStoredSamplesTTLMicros = 60 * 60 * 1e6;

@interface LSSyncSample : NSObject<NSCoding>

- (id) initWithDelayMicros:(UInt64)delayMicros offsetMicros:(UInt64)offsetMicros;

@property (nonatomic) UInt64 delayMicros;
@property (nonatomic) UInt64 offsetMicros;

@end

@implementation LSSyncSample

- (id) initWithDelayMicros:(UInt64)delayMicros offsetMicros:(UInt64)offsetMicros
{
    if (self = [super init]) {
        self.delayMicros = delayMicros;
        self.offsetMicros = offsetMicros;
    }
    return self;
}

static NSString* kDelayKey = @"delay";
static NSString* kOffsetKey = @"offset";

- (id) initWithCoder:(NSCoder* )aDecoder {
    return [self initWithDelayMicros:[aDecoder decodeInt64ForKey:kDelayKey] offsetMicros:[aDecoder decodeInt64ForKey:kOffsetKey]];
}

- (void) encodeWithCoder:(NSCoder* )aCoder
{
    [aCoder encodeInt64:self.delayMicros forKey:kDelayKey];
    [aCoder encodeInt64:self.offsetMicros forKey:kOffsetKey];
}

@end

@implementation LSClockState {
    __weak LSTracer* m_tracer;
    NSMutableArray* m_samples;  // elements are LSSyncSamples
    UInt64 m_currentOffsetMicros;
    int m_currentOffsetAge;
}

- (id) initWithLSTracer:(LSTracer*)tracer
{
    if (self = [super init]) {
        self->m_tracer = tracer;
        [self _tryToRestoreFromUserDefaults];
        [self update];
    }
    return self;
}

+ (UInt64) nowMicros {
    return (UInt64)([[NSDate date] timeIntervalSince1970] * USEC_PER_SEC);
}

- (NSString*)_userDefaultsKey {
    return @"com.lightstep.clock_state";
}

static NSString* kTimestampMicrosKey = @"timestamp_micros";
static NSString* kSamplesKey = @"samples";

- (void)_persistToUserDefaults
{
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:
                    @{kTimestampMicrosKey: @([LSClockState nowMicros]),
                      kSamplesKey: m_samples}];
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:[self _userDefaultsKey]];
}

// Overwrites all state; only intended to be called from initWithLSTracer.
- (void)_tryToRestoreFromUserDefaults
{
    self->m_samples = [NSMutableArray array];
    self->m_currentOffsetMicros = 0;
    self->m_currentOffsetAge = kMaxOffsetAge + 1;
    NSData* data = [[NSUserDefaults standardUserDefaults] objectForKey:[self _userDefaultsKey]];
    if (data != nil) {
        // Check out this gem, which ends with an emphatic "*Do not use NSKeyedArchiver*":
        //   http://stackoverflow.com/a/17301208/3399080
        @try {
            NSDictionary* dict = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            NSNumber* tsMicros = [dict objectForKey:kTimestampMicrosKey];
            NSArray* samples = [dict objectForKey:kSamplesKey];
            if (dict && tsMicros && samples &&
                (tsMicros.longLongValue > ([LSClockState nowMicros] - kStoredSamplesTTLMicros))) {
                NSUInteger loc = MAX(0, samples.count - (kMaxOffsetAge + 1));
                NSUInteger len = samples.count - loc;
                m_samples = [NSMutableArray arrayWithArray:[samples subarrayWithRange:NSMakeRange(loc, len)]];
            }
        }
        @catch (NSException* e) {
            NSLog(@"Unable to decode LSClockState data. Leaving things be.");
        }
    }
    if (m_samples.count == 0) {
        // Otherwise initalize with (kMaxOffsetAge+1) dummy samples.
        for (int i = 0; i < (kMaxOffsetAge+1); i++) {
            LSSyncSample* ss = [[LSSyncSample alloc] initWithDelayMicros:INT64_MAX offsetMicros:0];
            [m_samples addObject:ss];
        }
    }
}

// Callers should hold a lock while calling
- (id<NSCoding>)_getObjectForKey:(NSString* )key
{
    NSData* data = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (data != nil) {
        // Check out this gem, which ends with an emphatic "*Do not use NSKeyedArchiver*":
        //   http://stackoverflow.com/a/17301208/3399080
        @try {
            return [NSKeyedUnarchiver unarchiveObjectWithData:data];
        }
        @catch (NSException* e) {
            NSLog(@"Unable to decode object for key: %@", key);
            return nil;
        }
    }

    return nil;
}

- (void) addSampleWithOriginMicros:(UInt64)originMicros receiveMicros:(UInt64)receiveMicros transmitMicros:(UInt64)transmitMicros destinationMicros:(UInt64)destinationMicros
{
    UInt64 latestDelayMicros = INT64_MAX;
    UInt64 latestOffsetMicros = 0;
    // Ensure that all of the data are valid before using them. If
    // not, we'll push a {0, MAX} record into the queue.
    if (originMicros > 0 && receiveMicros > 0 &&
        transmitMicros > 0 && destinationMicros > 0) {
        latestDelayMicros = (destinationMicros - originMicros) - (transmitMicros - receiveMicros);
        latestOffsetMicros = ((receiveMicros - originMicros) + (transmitMicros - destinationMicros)) / 2;
    }

    // Discard the oldest sample and push the new one.
    [m_samples removeObjectAtIndex:0];
    [m_samples addObject:[[LSSyncSample alloc] initWithDelayMicros:latestDelayMicros offsetMicros:latestOffsetMicros]];
    m_currentOffsetAge++;

    // Remember what we've seen.
    [self _persistToUserDefaults];

    // Take the new sample into account.
    [self update];
}

- (void) update
{
    // This is simplified version of the clock filtering in Simple
    // NTP. It ignores precision and dispersion (frequency error). In
    // brief, it keeps the 8 (kMaxOffsetAge+1) most recent
    // delay-offset pairs, and considers the offset with the smallest
    // delay to be the best one. However, it only uses this new offset
    // if the change (relative to the last offset) is small compared
    // to the estimated error.
    //
    // See:
    // https://tools.ietf.org/html/rfc5905#appendix-A.5.2
    // http://books.google.com/books?id=pdTcJBfnbq8C
    //   esp. section 3.5
    // http://www.eecis.udel.edu/~mills/ntp/html/filter.html
    // http://www.eecis.udel.edu/~mills/database/brief/algor/algor.pdf
    // http://www.eecis.udel.edu/~mills/ntp/html/stats.html
    //
    // TODO: Consider huff-n'-puff if we think the delays are highly
    // asymmetric.
    // http://www.eecis.udel.edu/~mills/ntp/html/huffpuff.html

    // Find the sample with the smallest delay; the corresponding
    // offset is the "best" one.
    UInt64 minDelayMicros = INT64_MAX;
    UInt64 bestOffsetMicros = 0;
    for (int i = 0; i < m_samples.count; i++) {
        LSSyncSample* curSamp = m_samples[i];
        if (curSamp.delayMicros < minDelayMicros) {
            minDelayMicros = curSamp.delayMicros;
            bestOffsetMicros = curSamp.offsetMicros;
        }
    }

    // No update.
    if (bestOffsetMicros == m_currentOffsetMicros) {
        return;
    }

    // Now compute the jitter, i.e., the error relative to the new
    // offset were we to use it.
    double jitter = 0;
    for (int i = 0; i < m_samples.count; i++) {
        LSSyncSample* curSamp = m_samples[i];
        jitter += pow(bestOffsetMicros - curSamp.offsetMicros, 2);
    }
    jitter = sqrt(jitter / m_samples.count);

    // Ignore spikes: only use the new offset if the change is not too
    // large... unless the current offset is too old. The "too old"
    // condition is also triggered when update() is called from the
    // constructor.
    static const int kSGATE = 3; // See RFC 5905
    if (m_currentOffsetAge > kMaxOffsetAge ||
        llabs((int64_t)m_currentOffsetMicros - (int64_t)bestOffsetMicros) < kSGATE * jitter) {
        m_currentOffsetMicros = bestOffsetMicros;
        m_currentOffsetAge = 0;
    }
}

- (UInt64) offsetMicros
{
    return m_currentOffsetMicros;
}

@end
