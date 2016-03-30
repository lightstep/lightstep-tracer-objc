#include <UIKit/UIKit.h>

/**
 * Shared, generic utility functions used across the library.
 */
@interface LSUtil : NSObject

+ (UInt64)generateGUID;
+ (NSString*)hexGUID:(UInt64)guid;
+ (UInt64)guidFromHex:(NSString*)hexString;
+ (NSString*)objectToJSONString:(id)obj maxLength:(NSUInteger)maxLength;

@end

@interface NSDate (LSSpan)
- (int64_t) toMicros;
@end
