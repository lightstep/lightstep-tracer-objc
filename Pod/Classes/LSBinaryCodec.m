//
//  LSBinaryCodec.m
//

#import "LSBinaryCodec.h"
#import "LSSpanContext.h"
#import "OTTracer.h"


@implementation LSBinaryCodec

+ (NSData *)encodedMessageForTraceID:(UInt64)traceID
                              spanID:(UInt64)spanID
                             baggage:(NSDictionary *)baggage {
    // Encode our inner message first
    NSData *inner = [LSBinaryCodec encodeInnerMessageForTraceID:traceID spanID:spanID baggage:baggage];

    // Next, write our outer message by checking the length of the inner message.
    // TODO: We probably know this capacity, so we should set it:
    NSMutableData *outer = [[NSMutableData alloc] init];

    // BasicCarrier basic_ctx = 2;
    [LSBinaryCodec writeTagNumber:2 format:WireFormatMessage buffer:outer];
    [LSBinaryCodec writeVarintEncodedUInt64:inner.length buffer:outer];
    [outer appendData:inner];

    return outer;
}

+ (BOOL)decodeMessage:(NSData *)protoEnc
                 into:(id)dest
                error:(NSError *__autoreleasing *)errorPtr {
    // Read our keys and values until we get to our embedded message:
    UInt64 head = 0;
    UInt64 tail = head + protoEnc.length;
    while (head < tail) {
        KeyInfo keyInfo = [LSBinaryCodec nextKeyFromProto:protoEnc offset:&head];
        if (keyInfo.fieldNum != 2) {
            // Skip ahead past the data.
            switch (keyInfo.fieldType) {
                case WireFormatVarint:
                {
                    [LSBinaryCodec readVarintFromProto:protoEnc startingAt:&head];
                    break;
                }
                case WireFormatFixed64:
                case WireFormatFixed32:
                case WireFormatLengthDelim:
                    head += keyInfo.length;
                default:
                    if (errorPtr) {
                        *errorPtr = [NSError errorWithDomain:OTErrorDomain
                                                        code:OTInvalidCarrierCode
                                                    userInfo:nil];
                    }
            }
        } else {
            NSData *msg = [protoEnc subdataWithRange:NSMakeRange(head, keyInfo.length)];
            LSSpanContext *decoded = dest;
            bool success = [LSBinaryCodec decodeEmbeddedMessage:msg dest:decoded withError:errorPtr];
            if (!success) {
                // TODO: Do something here
                return NO;
            }
            return YES;
        }
    }

    if (errorPtr) {
        *errorPtr = [NSError errorWithDomain:OTErrorDomain code:OTSpanContextCorruptedCode userInfo:nil];
    }
    return NO;
}

#pragma mark - private

typedef struct _keyInfo {
    Byte fieldType;
    UInt64 fieldNum;
    // Non-zero for only fixed-width or length-delimited field types.
    // 0 for Varint, 8 for fixed64, NumBytes for length-delimited fields.
    NSUInteger length;
} KeyInfo;

+ (NSData *)encodeInnerMessageForTraceID:(UInt64)traceID
                                  spanID:(UInt64)spanID
                                 baggage:(NSDictionary *)baggage {
    NSMutableData *message = [[NSMutableData alloc] init];

    // fixed64 traceID = 1;
    [LSBinaryCodec writeTagNumber:1 format:WireFormatFixed64 buffer:message];
    [LSBinaryCodec writeFixedEncodedUInt64:traceID buffer:message];

    // fixed64 spanID = 2;
    [LSBinaryCodec writeTagNumber:2 format:WireFormatFixed64 buffer:message];
    [LSBinaryCodec writeFixedEncodedUInt64:spanID buffer:message];

    // bool sampled = 3; (always true here)
    [LSBinaryCodec writeTagNumber:3 format:WireFormatBool buffer:message];
    [LSBinaryCodec writeVarintEncodedUInt64:YES buffer:message];

    // map<string, string> baggage = 4;
    [LSBinaryCodec writeStringMap:baggage tagNumber:4 buffer:message];

    return message;
}

+ (bool)decodeEmbeddedMessage:(NSData *)msg
                         dest:(LSSpanContext *)dest
                    withError:(NSError*__autoreleasing *)errorPtr {
    UInt64 head = 0;
    UInt64 tail = head + msg.length;
    UInt64 traceId = 0;
    UInt64 spanId = 0;
    NSMutableDictionary *baggage = [NSMutableDictionary dictionary];

    if (head >= tail) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:OTErrorDomain code:OTInvalidCarrierCode userInfo:nil];
        }
        return false;
    }

    while (head < tail) {
        KeyInfo keyInfo = [LSBinaryCodec nextKeyFromProto:msg offset:&head];
        switch (keyInfo.fieldNum) {
            case 1: // trace_id
                traceId = [LSBinaryCodec readLittleEndianUInt64From:msg offset:&head];
                break;
            case 2: // span_id
                spanId = [LSBinaryCodec readLittleEndianUInt64From:msg offset:&head];
                break;
            // Skip case 3: // sampled because LightStep doesn't use this OT concept.
            case 4: // baggage item. We can have many of these.
            {
                // map<string, string> baggage = 4; is equivalent on the wire to:
                // message Entry {
                //   string key = 1;
                //   string value = 2;
                // }
                // repeated Entry = 4;

                // Read the key, advance head.
                KeyInfo mapKeyInfo = [LSBinaryCodec nextKeyFromProto:msg offset:&head];

                NSString *key = [[NSString alloc] initWithData:[msg subdataWithRange:NSMakeRange(head, mapKeyInfo.length)] encoding:NSUTF8StringEncoding];

                head += mapKeyInfo.length;

                // Read the value, advance head.
                KeyInfo mapValueInfo = [LSBinaryCodec nextKeyFromProto:msg offset:&head];
                NSString *value = [[NSString alloc] initWithData:[msg subdataWithRange:NSMakeRange(head, mapValueInfo.length)] encoding:NSUTF8StringEncoding];

                // Add it to our baggage dictionary.
                [baggage setObject:value forKey:key];
                break;
            }
            default:
                // Ignore other fields.
                break;
        }
    }

    if (traceId == 0 || spanId == 0) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:OTErrorDomain code:OTInvalidCarrierCode userInfo:nil];
        }
        return false;
    }

    // What if there was no baggage? Just an empty dict then, nbd.
    [dest initWithTraceId:traceId spanId:spanId baggage:baggage];

    return true;
}


// Reads the UInt64 out of the bytes presented in little endian form. Advances the offset past this number.
+ (UInt64)readLittleEndianUInt64From:(NSData *)data offset:(UInt64 *)offset {
    UInt64 value = OSReadLittleInt64(data.bytes, *offset);
    *offset += sizeof(UInt64);
    return value;
}

// Reads the info for the next key in the protobuf file, advances offset to the start of the field
// for this key.
const UInt64 kFieldTypeMask = 0x7;

+ (KeyInfo)nextKeyFromProto:(NSData *)protoEnc offset:(UInt64 *)offset {
    UInt64 varint = [LSBinaryCodec readVarintFromProto:protoEnc startingAt:offset];

    KeyInfo keyInfo;
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
            UInt64 length = [LSBinaryCodec readVarintFromProto:protoEnc startingAt:offset];
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
    [LSBinaryCodec writeVarintEncodedUInt64:value buffer:buffer];
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
        [LSBinaryCodec writeTagNumber:1 format:WireFormatString buffer:oneEntry];
        [LSBinaryCodec writeVarintEncodedUInt64:kl buffer:oneEntry];
        [oneEntry appendData:[key dataUsingEncoding:NSUTF8StringEncoding]];

        NSString *value = (NSString *)v;
        NSUInteger vl = [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        [LSBinaryCodec writeTagNumber:2 format:WireFormatString buffer:oneEntry];
        [LSBinaryCodec writeVarintEncodedUInt64:vl buffer:oneEntry];
        [oneEntry appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];

        // Write the message tag + type.
        [LSBinaryCodec writeTagNumber:tagNumber format:WireFormatMap buffer:buffer];

        // Write the total message length
        [LSBinaryCodec writeVarintEncodedUInt64:oneEntry.length buffer:buffer];

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

// Field Types are stored in the bottom 3 bits of the field varint
Byte const WireFormatBool = 0;
Byte const WireFormatVarint = 0;
Byte const WireFormatFixed64 = 1;
Byte const WireFormatString = 2;
Byte const WireFormatMessage = 2;
Byte const WireFormatLengthDelim = 2;
Byte const WireFormatMap = 2;
Byte const WireFormatFixed32 = 5;

@end
