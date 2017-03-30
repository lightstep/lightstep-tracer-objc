//
//  LSBinaryCodec.h
//

#import <Foundation/Foundation.h>
#import "LSSpanContext.h"

#ifndef LSBinaryCodec_h
#define LSBinaryCodec_h


// Encodes or decodes trace data for LightStep's binary carrier format. The definition of
// the message is:
// https://github.com/lightstep/lightstep-tracer-common/blob/master/lightstep_carrier.proto

// This codec only uses the "BasicTracerCarrier" embedded message and ignores the deprecated
// field with tag 1.
@interface LSBinaryCodec : NSObject

+ (NSData *)encodedMessageForTraceID:(UInt64)traceID spanID:(UInt64)spanID baggage:(NSDictionary *)baggage;
+ (BOOL)decodeMessage:(NSData *)protoEnc into:(id)dest error:(NSError **)error;

@end

#endif /* LSBinaryCodec_h */
