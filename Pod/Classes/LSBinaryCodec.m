//
//  LSBinaryCodec.m
//

#import "LSBinaryCodec.h"
#import "LSPBUtil.h"
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
    [LSPBUtil writeTagNumber:2 format:PBFormatDelimited buffer:outer];
    [LSPBUtil writeVarintEncodedUInt64:inner.length buffer:outer];
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
        LSPBKeyInfo keyInfo = [LSPBUtil nextKeyFromProto:protoEnc offset:&head];
        if (keyInfo.fieldNum != 2) {
            // Skip ahead past the data.
            switch (keyInfo.fieldType) {
                case PBFormatVarint :
                {
                    [LSPBUtil readVarintFromProto:protoEnc startingAt:&head];
                    break;
                }
                case PBFormatFixed64:
                case PBFormatFixed32:
                case PBFormatDelimited:
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

+ (NSData *)encodeInnerMessageForTraceID:(UInt64)traceID
                                  spanID:(UInt64)spanID
                                 baggage:(NSDictionary *)baggage {
    NSMutableData *message = [[NSMutableData alloc] init];

    // fixed64 traceID = 1;
    [LSPBUtil writeTagNumber:1 format:PBFormatFixed64 buffer:message];
    [LSPBUtil writeFixedEncodedUInt64:traceID buffer:message];

    // fixed64 spanID = 2;
    [LSPBUtil writeTagNumber:2 format:PBFormatFixed64 buffer:message];
    [LSPBUtil writeFixedEncodedUInt64:spanID buffer:message];

    // bool sampled = 3; (always true here)
    [LSPBUtil writeTagNumber:3 format:PBFormatVarint buffer:message];
    [LSPBUtil writeVarintEncodedUInt64:YES buffer:message];

    // map<string, string> baggage = 4;
    [LSPBUtil writeStringMap:baggage tagNumber:4 buffer:message];

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
        LSPBKeyInfo keyInfo = [LSPBUtil nextKeyFromProto:msg offset:&head];
        switch (keyInfo.fieldNum) {
            case 1: // trace_id
                traceId = [LSPBUtil readLittleEndianUInt64From:msg offset:&head];
                break;
            case 2: // span_id
                spanId = [LSPBUtil readLittleEndianUInt64From:msg offset:&head];
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


                LSPBKeyInfo mapKeyInfo = [LSPBUtil nextKeyFromProto:msg offset:&head];
                if (mapKeyInfo.fieldType != PBFormatDelimited || mapKeyInfo.length == 0) {
                    if (errorPtr) {
                        *errorPtr = [NSError errorWithDomain:OTErrorDomain code:OTInvalidCarrierCode userInfo:nil];
                    }
                    return false;
                }
                NSString *key = [[NSString alloc] initWithData:[msg subdataWithRange:NSMakeRange(head, mapKeyInfo.length)] encoding:NSUTF8StringEncoding];
                head += mapKeyInfo.length;


                LSPBKeyInfo mapValueInfo = [LSPBUtil nextKeyFromProto:msg offset:&head];
                if (mapValueInfo.fieldType != PBFormatDelimited || mapValueInfo.length == 0) {
                    if (errorPtr) {
                        *errorPtr = [NSError errorWithDomain:OTErrorDomain code:OTInvalidCarrierCode userInfo:nil];
                    }
                    return false;
                }
                NSString *value = [[NSString alloc] initWithData:[msg subdataWithRange:NSMakeRange(head, mapValueInfo.length)] encoding:NSUTF8StringEncoding];
                head += mapValueInfo.length;

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

@end
