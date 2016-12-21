#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GPBTimestamp;

/**
 * Shared, generic utility functions used across the library.
 */
@interface LSUtil : NSObject

+ (UInt64)generateGUID;
+ (NSString*)hexGUID:(UInt64)guid;
+ (UInt64)guidFromHex:(NSString*)hexString;
+ (NSString*)objectToJSONString:(nullable id)obj maxLength:(NSUInteger)maxLength;
+ (GPBTimestamp*)protoTimestampFromMicros:(UInt64)micros;
+ (GPBTimestamp*)protoTimestampFromDate:(NSDate*)date;
+ (UInt64)microsFromProtoTimestamp:(GPBTimestamp*)protoTimestamp;
+ (NSMutableArray*)keyValueArrayFromDictionary:(NSDictionary<NSString*, NSObject*>*)dict;

@end

@interface NSDate (LSSpan)
- (int64_t) toMicros;
@end

NS_ASSUME_NONNULL_END
