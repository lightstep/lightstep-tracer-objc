// Move references to the Thrift internals here to avoid exposing the details
// in the public headers. This is not merely a code cleanliness issue as the
// added interfaces can affect Xcode's type resolution.
#import "crouton.h"

@interface LSTracer ()

/**
 * Record a span.
 */
- (void) _appendSpanRecord:(RLSpanRecord*)spanRecord;

@end