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

// Reads a fixed-width encoding of 64 bit integers from the data, advancing offset at the same time.
+ (UInt64)readLittleEndianUInt64From:(NSData *)data offset:(UInt64 *)offset;

// Reads the field's tag value and length from the data, advancing the offset at the same time.
+ (LSPBKeyInfo)nextKeyFromProto:(NSData *)protoEnc offset:(UInt64 *)offset;

// Reads a varint-encoded integer from the data, advancing the offset at the same time.
+ (UInt64)readVarintFromProto:(NSData *)proto startingAt:(UInt64 *)offset;

// Writes the tag number and field format into the buffer as a varint.
// @see https://developers.google.com/protocol-buffers/docs/encoding#structure
+ (void)writeTagNumber:(UInt64)tagNumber format:(Byte)format buffer:(NSMutableData *)buffer;

// Writes a NSDictionary containing only NSString * keys and values as a repeated entry to the buffer.
+ (void)writeStringMap:(NSDictionary *)data tagNumber:(UInt64)tagNumber buffer:(NSMutableData *)buffer;

// Writes a UInt64 in the fixed, little-endian encoding to the buffer.
+ (void)writeFixedEncodedUInt64:(UInt64)number buffer:(NSMutableData *)buffer;

// Writes a UInt64 in the varint encoding to the buffer.
+ (void)writeVarintEncodedUInt64:(UInt64)number buffer:(NSMutableData *)buffer;

@end

#endif /* LSPBUtil_h */
