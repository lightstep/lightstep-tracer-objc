#import <Foundation/Foundation.h>
#import <opentracing/OTSpan.h>
NS_ASSUME_NONNULL_BEGIN

@class LSSpanContext;
@class LSTracer;

/// An `LSSpan` represents a logical unit of work done by the service. One or
/// more spans – presumably from different processes – are assembled into traces.
///
/// The LSSpan class is thread-safe.
@interface LSSpan : NSObject<OTSpan>

#pragma mark - OpenTracing API

@property(nonatomic, strong, readonly) id<OTSpanContext> context;
@property(nonatomic, strong, readonly) LSTracer *tracer;
@property(atomic, strong) NSString *operationName;

- (void)setTag:(NSString*)key value:(NSString*)value;

- (void)log:(NSDictionary<NSString *, NSObject *> *)fields;
- (void)log:(NSDictionary<NSString *, NSObject *> *)fields timestamp:(nullable NSDate *)timestamp;
- (void)logEvent:(NSString *)eventName;
- (void)logEvent:(NSString *)eventName payload:(nullable NSObject*)payload;
- (void)log:(NSString *)eventName
  timestamp:(nullable NSDate *)timestamp
    payload:(nullable NSObject *)payload;

- (void)finish;
- (void)finishWithTime:(nullable NSDate *)finishTime;

- (id<OTSpan>)setBaggageItem:(NSString *)key value:(NSString*)value;
- (NSString*)getBaggageItem:(NSString *)key;


#pragma mark - LightStep extensions and internal methods

@property(nonatomic, strong, readonly) NSDate *startTime;

/// Internal function.
/// Creates a new span associated with the given tracer.
- (instancetype)initWithTracer:(LSTracer *)tracer;

/// Internal function.
/// Creates a new span associated with the given tracer and the other optional parameters.
- (instancetype)initWithTracer:(LSTracer *)tracer
                 operationName:(NSString *)operationName
                        parent:(nullable id<OTSpanContext>)parent
                          tags:(nullable NSDictionary<NSString *, NSString *> *)tags
                     startTime:(nullable NSDate *)startTime;

/// Get a particular tag.
- (NSString*)tagForKey:(NSString *)key;

///Generate a URL to the trace containing this span on LightStep.
- (NSURL*)_generateTraceURL;


// For testing only
- (NSDictionary*)_toJSONWithFinishTime:(NSDate*)finishTime;

@end
NS_ASSUME_NONNULL_END
