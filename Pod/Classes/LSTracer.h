#import <Foundation/Foundation.h>

#import "crouton.h"
#import "LSSpan.h"

FOUNDATION_EXPORT NSString *const LSFormatSplitText;

FOUNDATION_EXPORT NSString *const LSFormatBinary;

/**
 * The entrypoint to instrumentation for Cocoa.
 *
 * As early as feasible in the life of the application (e.g., in 
 * `application:didFinishLaunchingWithOptions:`), call one of the static 
 * `+[LSTracer initGlobalTracer...]` methods; `LSTracer` calls made prior to
 * that initialization will be dropped.
 *
 * LSTracer is thread-safe.
 */
@interface LSTracer : NSObject

#pragma mark - Shared instance initialization

/**
 * @see `+[LSTracer initGlobalTracer:groupName:hostport]` for parameter details.
 *
 * @return An `LSTracer` instance that's ready to create spans and logs.
 */
+ (instancetype) initGlobalTracer:(NSString*)accessToken;

/**
 * @see `+[LSTracer initGlobalTracer:groupName:hostport]` for parameter details.
 *
 * @return An `LSTracer` instance that's ready to create spans and logs.
 */
+ (instancetype) initGlobalTracer:(NSString*)accessToken
                        groupName:(NSString*)groupName;

/**
 * Call this early in the application lifecycle (calls to 'globalTracer' will 
 * return nil beforehand).
 *
 * @param accessToken the access token.
 * @param groupName the "group name" to associate with spans from this process; 
 *     e.g., the name of your iOS app or the bundle name.
 * @param hostport the reporting service hostport, defaulting to LSDefaultLightStepReportingHostport.
 *
 * @return An `LSTracer` instance that's ready to create spans and logs.
 */
+ (instancetype) initGlobalTracer:(NSString*)accessToken
                        groupName:(NSString*)groupName
                         hostport:(NSString*)hostport;

/**
 * Call this to get the shared `LSTracer` singleton instance 
 * post-initialization. Calls prior to initialization will return `nil`.
 *
 * @return the previously-initialized `LSTracer` instance, or `nil` if called 
 * prior to initialization.
 */
+ (instancetype) globalTracer;

/**
 * Alias for `globalTracer` based on a common singleton naming convention.
 */
+ (instancetype) sharedInstance;

#pragma mark - OpenTracing API

/**
 * Start a new root span with the given operation name.
 */
- (LSSpan*)startSpan:(NSString*)operationName;

/**
 * Start a new root span with the given operation name and tags.
 */
- (LSSpan*)startSpan:(NSString*)operationName
                tags:(NSDictionary*)tags;

/**
 * Start a new root span with the given operation name and other optional
 * parameters.
 */
- (LSSpan*)startSpan:(NSString*)operationName
              parent:(LSSpan*)parentSpan;

/**
 * Start a new root span with the given operation name and other optional
 * parameters.
 */
- (LSSpan*)startSpan:(NSString*)operationName
              parent:(LSSpan*)parentSpan
                tags:(NSDictionary*)tags;

/**
 * Start a new root span with the given operation name and other optional 
 * parameters.
 */
- (LSSpan*)startSpan:(NSString*)operationName
              parent:(LSSpan*)parentSpan
                tags:(NSDictionary*)tags
           startTime:(NSDate*)startTime;

/**
 * Transfer the span information into the carrier of the given format.
 */
- (void)inject:(LSSpan*)span format:(NSString*)format carrier:(id)carrier;

/**
 * Create a new span from the carrier of the given format.
 */
- (LSSpan*)join:(NSString*)operationName format:(NSString*)format carrier:(id)carrier;

/**
 * Flush any buffered data to the collector.
 */
- (void)flush;

#pragma mark - LightStep extensions and internal methods

/**
 * Record a span.
 */
- (void) _appendSpanRecord:(RLSpanRecord*)spanRecord;

/**
 * Record a log record.
 */
- (void) _appendLogRecord:(RLLogRecord*)logRecord;

/**
 *
 */
- (bool) enabled;

/**
 * The remote service URL string (as derived from `sharedInstancWithServiceHostport:token:`).
 */
@property (nonatomic, readonly) NSString* serviceUrl;

/**
 * The `LSTracer` instance's globally unique id ("guid"), which is both immutable and assigned automatically by LightStep.
 */
@property (nonatomic, readonly) NSString* runtimeGuid;


/**
 * The `LSTracer` instance's maximum number of records to buffer between reports.
 */
@property (atomic) NSUInteger maxLogRecords;

/**
 * The `LSTracer` instance's maximum number of records to buffer between reports.
 */
@property (atomic) NSUInteger maxSpanRecords;

/**
 * Maximum string length of any single JSON payload.
 */
@property (atomic) NSUInteger maxPayloadJSONLength;


@end