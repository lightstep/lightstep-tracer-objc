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
    // ignored for now.

    return message;
}

@end
