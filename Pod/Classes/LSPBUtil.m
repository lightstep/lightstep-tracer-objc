//
//  LSPBUtil.m
//  Pods
//
//  Created by Joe Blubaugh on 3/30/17.
//
//

#import <Foundation/Foundation.h>
#import "LSPBUtil.h"

// Field Types are stored in the bottom 3 bits of the field varint
Byte const WireFormatBool = 0;
Byte const WireFormatVarint = 0;
Byte const WireFormatFixed64 = 1;
Byte const WireFormatString = 2;
Byte const WireFormatMessage = 2;
Byte const WireFormatLengthDelim = 2;
Byte const WireFormatMap = 2;
Byte const WireFormatFixed32 = 5;

@implementation LSPBUtil

// Reads the UInt64 out of the bytes presented in little endian form. Advances the offset past this number.
+ (UInt64)readLittleEndianUInt64From:(NSData *)data offset:(UInt64 *)offset {
    UInt64 value = OSReadLittleInt64(data.bytes, *offset);
    *offset += sizeof(UInt64);
    return value;
}

// Reads the info for the next key in the protobuf file, advances offset to the start of the field
// for this key.
const UInt64 kFieldTypeMask = 0x7;

+ (LSPBKeyInfo)nextKeyFromProto:(NSData *)protoEnc offset:(UInt64 *)offset {
    UInt64 varint = [LSPBUtil readVarintFromProto:protoEnc startingAt:offset];

    LSPBKeyInfo keyInfo;
    keyInfo.fieldNum =  varint >> 3;
    keyInfo.fieldType = varint & kFieldTypeMask;

    switch (keyInfo.fieldType) {
        case WireFormatVarint:
            keyInfo.length = 0;
            break;
        case WireFormatFixed64:
            keyInfo.length = sizeof(UInt64);
            break;
        case WireFormatFixed32:
            keyInfo.length = sizeof(UInt32);
            break;
        case WireFormatLengthDelim:
        {
            UInt64 length = [LSPBUtil readVarintFromProto:protoEnc startingAt:offset];
            keyInfo.length = length;
            break;
        }
        default:
            break;
    }

    return keyInfo;
}

// Reads a varint off the proto bytes, advances the offset to the next byte after the varint.
+ (UInt64)readVarintFromProto:(NSData *)proto startingAt:(UInt64 *)offset {
    UInt64 varint = 0;
    UInt32 shift = 0;
    while (shift < 64) {
        // Read a byte.
        Byte *datum = (Byte *)proto.bytes + (*offset * sizeof(Byte));
        *offset += 1;

        varint |= (*datum & 0x7F) << shift;
        shift += 7;

        // If MSB was not set, we're done.
        if ((*datum & 0x80) == 0) {
            return varint;
        }

        // Now you have a uint!
    }

    return 0;
}

+ (void)writeTagNumber:(UInt64)tagNumber format:(Byte)format buffer:(NSMutableData *)buffer {
    UInt64 value = tagNumber << 3 | format;
    [LSPBUtil writeVarintEncodedUInt64:value buffer:buffer];
}

+ (void)writeStringMap:(NSDictionary *)data tagNumber:(UInt64)tagNumber buffer:(NSMutableData *)buffer {
    for (id k in data) {
        id v = [data objectForKey:k];

        // TODO: Try to avoid this extra alloc?
        NSMutableData *oneEntry = [[NSMutableData alloc] init];

        // for key & value
        // Write the equivalent tag key.
        // Write the length.
        // Write the string bytes.

        NSString *key = (NSString *)k;
        NSUInteger kl = [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        [LSPBUtil writeTagNumber:1 format:WireFormatString buffer:oneEntry];
        [LSPBUtil writeVarintEncodedUInt64:kl buffer:oneEntry];
        [oneEntry appendData:[key dataUsingEncoding:NSUTF8StringEncoding]];

        NSString *value = (NSString *)v;
        NSUInteger vl = [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        [LSPBUtil writeTagNumber:2 format:WireFormatString buffer:oneEntry];
        [LSPBUtil writeVarintEncodedUInt64:vl buffer:oneEntry];
        [oneEntry appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];

        // Write the message tag + type.
        [LSPBUtil writeTagNumber:tagNumber format:WireFormatMap buffer:buffer];

        // Write the total message length
        [LSPBUtil writeVarintEncodedUInt64:oneEntry.length buffer:buffer];

        // Append the message itself
        [buffer appendData:oneEntry];
    }
}

+ (void)writeFixedEncodedUInt64:(UInt64)number buffer:(NSMutableData *)buffer {
    Byte writeBuf;

    // We *have* to write these bytes in little-endian format:
    writeBuf = number & 0xFF; [buffer appendBytes:&writeBuf length:sizeof(writeBuf)];
    writeBuf = (number >> 8) & 0xFF; [buffer appendBytes:&writeBuf length:sizeof(writeBuf)];
    writeBuf = (number >> 16) & 0xFF; [buffer appendBytes:&writeBuf length:sizeof(writeBuf)];
    writeBuf = (number >> 24) & 0xFF; [buffer appendBytes:&writeBuf length:sizeof(writeBuf)];
    writeBuf = (number >> 32) & 0xFF; [buffer appendBytes:&writeBuf length:sizeof(writeBuf)];
    writeBuf = (number >> 40) & 0xFF; [buffer appendBytes:&writeBuf length:sizeof(writeBuf)];
    writeBuf = (number >> 48) & 0xFF; [buffer appendBytes:&writeBuf length:sizeof(writeBuf)];
    writeBuf = (number >> 56) & 0xFF; [buffer appendBytes:&writeBuf length:sizeof(writeBuf)];
}

+ (void)writeVarintEncodedUInt64:(UInt64)number buffer:(NSMutableData *)data {

    Byte writeBuf;
    // Each byte in a varint is 7 bits of the number + a leading bit. The last byte has a 0 for its leading bit.
    if (number > 0xFFFFFFFFFFFFFF) { writeBuf = 0x80 | (number >> 56 & 0x7F); [data appendBytes:&writeBuf length:sizeof(writeBuf)]; }
    if (number > 0x1FFFFFFFFFFFF) { writeBuf = 0x80 | (number >> 49 & 0x7F); [data appendBytes:&writeBuf length:sizeof(writeBuf)]; }
    if (number > 0x3FFFFFFFFFF) { writeBuf = 0x80 | (number >> 42 & 0x7F); [data appendBytes:&writeBuf length:sizeof(writeBuf)]; }
    if (number > 0x7FFFFFFFF) { writeBuf = 0x80 | (number >> 35 & 0x7F); [data appendBytes:&writeBuf length:sizeof(writeBuf)]; }
    if (number > 0xFFFFFFF) { writeBuf = 0x80 | (number >> 28 & 0x7F); [data appendBytes:&writeBuf length:sizeof(writeBuf)]; }
    if (number > 0x1FFFFF) { writeBuf = 0x80 | (number >> 21 & 0x7F); [data appendBytes:&writeBuf length:sizeof(writeBuf)]; }
    if (number > 0x3FFF) { writeBuf = 0x80 | (number >> 14 & 0x7F); [data appendBytes:&writeBuf length:sizeof(writeBuf)]; }
    if (number > 0x7F) { writeBuf = 0x80 | (number >> 7 & 0x7F); [data appendBytes:&writeBuf length:sizeof(writeBuf)]; }
    
    writeBuf = number & 0x7F;
    [data appendBytes:&writeBuf length:sizeof(writeBuf)];
    
}


@end
