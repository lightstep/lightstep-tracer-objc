#import <Foundation/Foundation.h>

@class GPBTimestamp;

/**
 * Shared, generic utility functions used across the library.
 */
@interface LSUtil : NSObject

+ (UInt64)generateGUID;
+ (NSString*)hexGUID:(UInt64)guid;
+ (UInt64)guidFromHex:(NSString*)hexString;
+ (NSString*)objectToJSONString:(id)obj maxLength:(NSUInteger)maxLength;
+ (GPBTimestamp*)protoTimestampFromMicros:(UInt64)micros;
+ (GPBTimestamp*)protoTimestampFromDate:(NSDate*)date;

@end

@interface NSDate (LSSpan)
- (int64_t) toMicros;
@end
