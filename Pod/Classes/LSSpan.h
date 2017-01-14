#import <Foundation/Foundation.h>
#import <opentracing/OTSpan.h>
NS_ASSUME_NONNULL_BEGIN

@class LSSpanContext;
@class LSTracer;

/// An `LSSpan` represents a logical unit of work done by the service.
/// One or more spans – presumably from different processes – are assembled into traces.
///
/// The LSSpan class is thread-safe.
@interface LSSpan : NSObject<OTSpan>

#pragma mark - OpenTracing API

@property(atomic, strong, readonly) LSSpanContext *context;
@property(nonatomic, strong, readonly) LSTracer *tracer;
@property(atomic, strong) NSString *operationName;

- (void)setTag:(NSString *)key value:(NSString *)value;
- (void)log:(NSDictionary<NSString *, NSObject *> *)fields;
- (void)log:(NSDictionary<NSString *, NSObject *> *)fields timestamp:(nullable NSDate *)timestamp;
- (void)logEvent:(NSString *)eventName;
- (void)logEvent:(NSString *)eventName payload:(nullable NSObject *)payload;
- (void)log:(NSString *)eventName timestamp:(nullable NSDate *)timestamp payload:(nullable NSObject *)payload;

- (void)finish;
- (void)finishWithTime:(nullable NSDate *)finishTime;

- (id<OTSpan>)setBaggageItem:(NSString *)key value:(NSString *)value;
- (NSString *)getBaggageItem:(NSString *)key;

#pragma mark - LightStep extensions and internal methods

/// Internal function.
///
/// Creates a new span associated with the given tracer.
- (instancetype)initWithTracer:(LSTracer *)tracer;

/// Internal function.
///
/// Creates a new span associated with the given tracer and the other optional parameters.
- (instancetype)initWithTracer:(LSTracer *)tracer
                 operationName:(NSString *)operationName
                        parent:(nullable LSSpanContext *)parent
                          tags:(nullable NSDictionary *)tags
                     startTime:(nullable NSDate *)startTime;

@property(nonatomic, strong) NSDictionary<NSString *, NSString *> *tags;

/// Add a set of tags from the given dictionary. Existing key-value pairs will be overwritten by any new tags.
- (void)addTags:(NSDictionary *)tags;

///  Get a particular tag.
- (NSString *)tagForKey:(NSString *)key;

/// Generate a URL to the trace containing this span on LightStep.
- (NSURL *)traceURL;

/// For testing only
- (NSDictionary *)_toJSONWithFinishTime:(NSDate *)finishTime;

@property(nonatomic, strong, readonly) NSDate *startTime;

@end
NS_ASSUME_NONNULL_END
