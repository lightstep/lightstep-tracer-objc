#import <Foundation/Foundation.h>

#import <opentracing/OTTracer.h>
#import "LSSpan.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The error domain for all OpenTracing-related NSErrors.
 */
extern FOUNDATION_EXPORT const NSString *LSErrorDomain;
/**
 * OTUnsupportedFormat should be used by `OTTracer#inject:format:carrier:` and
 * `OTTracer#extractWithFormat:carrier:` implementations that don't support the
 * requested carrier format.
 */
extern FOUNDATION_EXPORT const NSInteger LSBackgroundTaskError;

/**
 * An implementation of the OTTracer protocol.
 *
 * Either pass the resulting id<OTTracer> around your application explicitly or use the OTGlobal singleton mechanism.
 *
 * LSTracer is thread-safe.
 *
 * @see OTGlobal
 */
@interface LSTracer: NSObject<OTTracer>

#pragma mark - LSTracer initialization

/**
 * @see `-[LSTracer initWithToken:componentName:baseURL]` for parameter details.
 *
 * @return An `LSTracer` instance that's ready to create spans and logs.
 */
- (instancetype)initWithToken:(NSString *)accessToken;

/**
 * @see `-[LSTracer initWithToken:componentName:baseURL]` for parameter details.
 *
 * @return An `LSTracer` instance that's ready to create spans and logs.
 */
- (instancetype)initWithToken:(NSString *)accessToken
                componentName:(nullable NSString *)componentName;

/**
 * @see `-[LSTracer initWithToken:componentName:baseURL:flushIntervalSeconds:]` for parameter details.
 *
 * @return An `LSTracer` instance that's ready to create spans and logs.
 */
- (instancetype)initWithToken:(NSString *)accessToken
                componentName:(nullable NSString *)componentName
         flushIntervalSeconds:(NSUInteger)flushIntervalSeconds;

/**
 * Initialize an LSTracer instance. Either pass the resulting LSTracer* around your application explicitly or use the
 * OTGlobal singleton mechanism.
 * Whether calling `-[LSTracer flush]` manually or whether using automatic background flushing, users may wish to
 * register for UIApplicationDidEnterBackgroundNotification notifications and explicitly call flush at that point.
 *
 *
 * @param accessToken the access token.
 * @param componentName the "component name" to associate with spans from this process; e.g., the name of your iOS app
 *        or the bundle name.
 * @param baseURL the URL for the collector's HTTP+JSON base endpoint (search for LSDefaultBaseURLString)
 * @param flushIntervalSeconds the flush interval, or 0 for no automatic background flushing
 *
 * @return An `LSTracer` instance that's ready to create spans and logs.
 *
 * @see OTGlobal
 */
- (instancetype)initWithToken:(NSString *)accessToken
                componentName:(nullable NSString *)componentName
                      baseURL:(nullable NSURL *)baseURL
         flushIntervalSeconds:(NSUInteger)flushIntervalSeconds;

#pragma mark - OpenTracing API

- (id<OTSpan>)startSpan:(NSString *)operationName;

- (id<OTSpan>)startSpan:(NSString *)operationName
                   tags:(nullable NSDictionary *)tags;

- (id<OTSpan>)startSpan:(NSString *)operationName
                childOf:(nullable id<OTSpanContext>)parentSpan;

- (id<OTSpan>)startSpan:(NSString *)operationName
                childOf:(nullable id<OTSpanContext>)parentSpan
                   tags:(nullable NSDictionary *)tags;

- (id<OTSpan>)startSpan:(NSString *)operationName
                childOf:(nullable id<OTSpanContext>)parentSpan
                   tags:(nullable NSDictionary *)tags
              startTime:(nullable NSDate *)startTime;

- (id<OTSpan>)startSpan:(NSString *)operationName
             references:(nullable NSArray *)references
                   tags:(nullable NSDictionary *)tags
              startTime:(nullable NSDate *)startTime;


- (BOOL)inject:(id<OTSpanContext>)span
        format:(NSString *)format
       carrier:(id)carrier;

- (BOOL)inject:(id<OTSpanContext>)span
        format:(NSString *)format
       carrier:(id)carrier
         error:(NSError* __autoreleasing  *)outError;


- (id<OTSpanContext>)extractWithFormat:(NSString *)format
                               carrier:(id)carrier;

- (id<OTSpanContext>)extractWithFormat:(NSString *)format
                               carrier:(id)carrier
                                 error:(NSError* __autoreleasing  *)outError;

#pragma mark - LightStep extensions and internal methods


/// The remote service base URL
@property (nonatomic, readonly) NSURL *baseURL;

/// `LSTracer` instance's globally unique id ("guid"), and assigned automatically by LightStep.
@property (nonatomic, readonly) UInt64 runtimeGuid;

/// The `LSTracer` instance's maximum number of records to buffer between reports.
@property (atomic) NSUInteger maxSpanRecords;

/// Maximum string length of any single JSON payload.
@property (atomic) NSUInteger maxPayloadJSONLength;

/// Returns true if the library is currently buffering and reporting data.
@property (atomic) BOOL enabled;

/// Tracer's access token
@property (atomic, readonly) NSString *accessToken;

/// Record a span.
- (void)_appendSpanJSON:(NSDictionary *)spanRecord;

/**
 * Flush any buffered data to the collector. Returns without blocking.
 *
 * If non-nil, doneCallback will be invoked once the flush()completes.
 */
- (void)flush:(nullable void (^)(NSError *_Nullable error))doneCallback;

@end

NS_ASSUME_NONNULL_END
