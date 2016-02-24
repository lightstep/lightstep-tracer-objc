//
//  RLClient.h
//

#import <Foundation/Foundation.h>

#import "crouton.h"

/**
 * The default host:port endpoint for the reporting library.
 */
extern NSString*const RLDefaultTraceguideReportingHostort;

/**
 * An `RLActiveSpan` represents an un-`finish`ed (i.e., "Active") span. One or more spans – presumably from different processes – are assembled into traces based on JoinIds, per `addJoinId:value:`. Each span also serves as a short-lived per-operation log.
 *
 * Create `RLActiveSpan`s via the `RLClient`'s `beginSpan:` method.
 */
@interface RLActiveSpan : NSObject
/**
 * Mark the end time and record this span. (Called automatically by the destructor if need be)
 */
- (void) finish;  // (also called automatically by dealloc)

/**
 * Add a JoinId for `key` and `value` to the given span. Note that an `endUserId` can be set for all spans in an `RLClient` via its `endUserId` property.
 *
 * @param key the JoinId key
 * @param value the JoinId value
 */
- (void) addJoinId:(NSString*)key value:(NSString*)value;

/**
 * Attach a log message to this `RLActiveSpan`.
 *
 * @param message the log contents.
 */
- (void) log:(NSString*)message;

/**
 * Attach a log message and structured payload to this `RLActiveSpan`.
 *
 * @param message the log contents.
 * @param payload an arbitrary structured payload which is serialized (in its entirety) along with the message.
 */
- (void) log:(NSString*)message payload:(NSDictionary*)payload;

/**
 * Attach an error log message to this `RLActiveSpan`.
 *
 * @param errorMessage the error log message
 */
- (void) logError:(NSString*)errorMessage;

@end

/**
 * The entrypoint to instrumentation for Cocoa.
 *
 * As early as feasible in the life of the application (e.g., in `application:didFinishLaunchingWithOptions:`), call one of the static `+[RLClient sharedInstanceWith...]` methods; `RLClient` calls made prior to that initialization will be dropped.
 *
 * If there is a single end-user per Cocoa application instance, take advantage of the `RLClient.endUserId` property.
 */
@interface RLClient : NSObject

/**----------------------------------------------
 * @name Initialization.
 *-----------------------------------------------
 */

/**
 * Call this early in the application lifecycle (calls to 'sharedInstance' will return nil beforehand).
 *
 * @param hostport the reporting service hostport, defaulting to RLDefaultTraceguideReportingHostport.
 * @param accessToken the access token.
 * @param groupName the "group name" to associate with spans from this process; e.g., the name of your iOS app or the bundle name.
 *
 * @return An `RLClient` instance that's ready to create spans and logs.
 */
+ (instancetype) sharedInstanceWithServiceHostport:(NSString*)hostport token:(NSString*)accessToken groupName:(NSString*)groupName;

/**
 * @see `+[RLClient sharedInstanceWithServiceHostport:token:groupName]` for parameter details.
 *
 * @return An `RLClient` instance that's ready to create spans and logs.
 */
+ (instancetype) sharedInstanceWithAccessToken:(NSString*)accessToken groupName:(NSString*)groupName;

/**
 * @see `+[RLClient sharedInstanceWithServiceHostport:token:groupName]` for parameter details.
 *
 * @return An `RLClient` instance that's ready to create spans and logs.
 */
+ (instancetype) sharedInstanceWithAccessToken:(NSString*)accessToken;

/**
 * Call this to get the shared `RLClient` singleton instance post-initialization. Calls prior to initialization will return `nil`.
 *
 * @return the previously-initialized `RLClient` instance, or `nil` if called prior to initialization.
 */
+ (instancetype) sharedInstance;

/**----------------------------------------------
 * @name Service configuration.
 *-----------------------------------------------
 */

/**
 * The remote service URL string (as derived from `sharedInstancWithServiceHostport:token:`).
 */
@property (nonatomic, readonly) NSString* serviceUrl;

/**
 * The `RLClient` instance's globally unique id ("guid"), which is both immutable and assigned automatically by LightStep.
 */
@property (nonatomic, readonly) NSString* runtimeGuid;


/**
 * The `RLClient` instance's maximum number of records to buffer between reports.
 */
@property (nonatomic) NSUInteger maxLogRecords;

/**
 * The `RLClient` instance's maximum number of records to buffer between reports.
 */
@property (nonatomic) NSUInteger maxSpanRecords;

/**----------------------------------------------
 * @name Client-wide end-user ids.
 *-----------------------------------------------
 */

/**
 * The current end-user's id, which should be consistent with the end-user ids used in LightStep instrumentation outside of the mobile app.
 *
 * One can always set a per-`RLActiveSpan` end-user id manually using `-[RLActiveSpan addJoinId:value:]`; the advantage of this property is that all spans from this `RLClient` will automatically have the respective join id added.
 */
@property (nonatomic, copy) NSString* endUserId;

/**
 * The key name for the endUserId's JoinId. Defaults to "end_user_id", but may be overridden.
 *
 * For instance, if you use a session id within the iOS app but don't always have client-side access to the endUserId used elsewhere in instrumentation, you might set `endUserKeyName` to `session_id`, and of course set `endUserId` proper to that session id value.
 *
 * One can always set a per-`RLActiveSpan` end-user id manually using `-[RLActiveSpan addJoinId:value:]`; the advantage of this property is that all spans from this `RLClient` will automatically have the respective join id added.
 */
@property (nonatomic, copy) NSString* endUserKeyName;

/**----------------------------------------------
 * @name Creating new spans
 *-----------------------------------------------
 */

/**
 * Mark the beginning of a new `RLActiveSpan`.
 *
 * @param operation the operation name for the new span.
 *
 * @return the newly-initialized `RLActiveSpan`. It is the caller's responsibility to call `-[RLActiveSpan finish]`.
 */
- (RLActiveSpan*) beginSpan:(NSString*)operation;

/**----------------------------------------------
 * @name Logging
 *-----------------------------------------------
 */

/**
 * See `-[RLActiveSpan log:]`
 */
- (void) log:(NSString*)message;
/**
 * See `-[RLActiveSpan log:payload:]`
 */
- (void) log:(NSString*)message payload:(NSDictionary*)payload;

/**
 * An experimental API that's closer to something like Mixpanel's `track`.
 *
 * @param stableName the `stableName` is, well, stable; it is more of a unique id than a descriptive log message.
 */
- (void) logStable:(NSString*)stableName payload:(NSDictionary*)payload;

/**
 * The fully-specified superset of the other logging calls.
 */
- (void) log:(NSString*)message stableName:(NSString*)stableName payload:(NSDictionary*)payload spanGuid:(NSString*)spanGuid;

/**----------------------------------------------
 * @name Miscellaneous
 *-----------------------------------------------
 */

/**
 * Explicitly flush to the LightStep collector (this is called periodically in the background, too).
 */
- (void) flushToService;

@end
