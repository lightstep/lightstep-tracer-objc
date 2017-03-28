#import <Foundation/Foundation.h>

#import "LSSpan.h"
#import <opentracing/OTTracer.h>

NS_ASSUME_NONNULL_BEGIN

/// The error domain for all LightStep-related NSErrors.
extern NSString *const LSErrorDomain;

/// LightStep error that represents background task failures.
extern NSInteger const LSBackgroundTaskError;

/// An implementation of the OTTracer protocol.

/// Either pass the resulting id<OTTracer> around your application explicitly or use the OTGlobal singleton
/// mechanism.
///
/// LSTracer is thread-safe.
@interface LSTracer : NSObject<OTTracer>

#pragma mark - LSTracer initialization

/// @returns An `LSTracer` instance that's ready to create spans and logs.
- (instancetype)initWithToken:(NSString *)accessToken;

/// @returns An `LSTracer` instance that's ready to create spans and logs.
- (instancetype)initWithToken:(NSString *)accessToken componentName:(nullable NSString *)componentName;

/// @returns An `LSTracer` instance that's ready to create spans and logs.
- (instancetype)initWithToken:(NSString *)accessToken
                componentName:(nullable NSString *)componentName
         flushIntervalSeconds:(NSUInteger)flushIntervalSeconds;

/// Initialize an LSTracer instance. Either pass the resulting LSTracer* around your application explicitly
/// or use the OTGlobal singleton mechanism.
/// Whether calling `-[LSTracer flush]` manually or whether using automatic background flushing, users may
/// wish to register for UIApplicationDidEnterBackgroundNotification notifications and explicitly call flush
/// at that point.
///
/// @param accessToken: the access token.
/// @param componentName: the "component name" to associate with spans from this process; e.g.,
///                       the name of your iOS app or the bundle name.
/// @param baseURL: the URL for the collector's HTTP+JSON base endpoint (search for LSDefaultBaseURLString)
/// @param flushIntervalSeconds: the flush interval, or 0 for no automatic background flushing
///
/// @returns An `LSTracer` instance that's ready to create spans and logs.
- (instancetype)initWithToken:(NSString *)accessToken
                componentName:(nullable NSString *)componentName
                      baseURL:(nullable NSURL *)baseURL
         flushIntervalSeconds:(NSUInteger)flushIntervalSeconds;


#pragma mark - LightStep extensions and internal methods

/// The remote service base URL
@property(nonatomic, strong, readonly) NSURL *baseURL;

/// `LSTracer` instance's globally unique id ("guid"), and assigned automatically by LightStep.
@property(nonatomic, readonly) UInt64 runtimeGuid;

/// HTTP session to be used for performing requests. This enables sharing a connnection pool with your own app.
/// It should be set during initialization, ideally before starting and finishing Spans.
@property(nonatomic, strong) NSURLSession *urlSession;

/// The `LSTracer` instance's maximum number of records to buffer between reports.
@property(atomic) NSUInteger maxSpanRecords;

/// Maximum string length of any single JSON payload.
@property(atomic) NSUInteger maxPayloadJSONLength;

/// If true, the library is currently buffering and reporting data. If set to false, tracing data is no longer
/// collected.
@property(atomic) BOOL enabled;

/// Tracer's access token
@property(atomic, strong, readonly) NSString *accessToken;

/// Record a span.
- (void)_appendSpanJSON:(NSDictionary *)spanRecord;

/// Flush any buffered data to the collector. Returns without blocking.
///
/// If non-nil, doneCallback will be invoked once the flush()completes.
- (void)flush:(nullable void (^)(NSError *_Nullable error))doneCallback;

@end

NS_ASSUME_NONNULL_END
