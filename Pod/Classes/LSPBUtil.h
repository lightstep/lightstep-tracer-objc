//
//  LSPBUtil.h
//

#import <Foundation/Foundation.h>

#ifndef LSPBUtil_h
#define LSPBUtil_h

// ProtoBuf Wire Formats
typedef enum {
    PBFormatVarint = 0,
    PBFormatFixed64 = 1,
    PBFormatDelimited = 2,
    PBFormatFixed32 = 5,
} PBFormat;

typedef struct _keyInfo {
    Byte fieldType;
    UInt64 fieldNum;
    // Non-zero for only fixed-width or length-delimited field types.
    // 0 for Varint, 8 for fixed64, NumBytes for length-delimited fields.
    NSUInteger length;
} LSPBKeyInfo;

@interface LSPBUtil : NSObject

+ (UInt64)readLittleEndianUInt64From:(NSData *)data offset:(UInt64 *)offset;
+ (LSPBKeyInfo)nextKeyFromProto:(NSData *)protoEnc offset:(UInt64 *)offset;
+ (UInt64)readVarintFromProto:(NSData *)proto startingAt:(UInt64 *)offset;
+ (void)writeTagNumber:(UInt64)tagNumber format:(Byte)format buffer:(NSMutableData *)buffer;
+ (void)writeStringMap:(NSDictionary *)data tagNumber:(UInt64)tagNumber buffer:(NSMutableData *)buffer;
+ (void)writeFixedEncodedUInt64:(UInt64)number buffer:(NSMutableData *)buffer;
+ (void)writeVarintEncodedUInt64:(UInt64)number buffer:(NSMutableData *)buffer;

@end

#endif /* LSPBUtil_h */
