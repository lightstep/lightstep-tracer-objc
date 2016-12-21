#import "LSUtil.h"
#import <stdlib.h>  // arc4random_uniform()

@implementation LSUtil

+ (UInt64)generateGUID {
    return (((UInt64)arc4random()) << 32) | arc4random();
}

+ (NSString*)hexGUID:(UInt64)guid {
    return [NSString stringWithFormat:@"%llx", guid];
}

+ (UInt64)guidFromHex:(NSString*)hexString {
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    UInt64 rval;
    if (![scanner scanHexLongLong:&rval]) {
        return 0; // what else to do?
    }
    return rval;
}

+ (NSString*)objectToJSONString:(id)obj
                      maxLength:(NSUInteger)maxLength {
    NSString* json = [LSUtil _objectToJSONString:obj];
    if ([json length] > maxLength) {
        NSLog(@"Dropping excessively large payload: length=%@", @([json length]));
        json = nil;
    }
    return json;
}

// Convert the object to JSON without string length constraints
+ (NSString*)_objectToJSONString:(id)obj {
    if (obj == nil) {
        return nil;
    } else if ([NSJSONSerialization isValidJSONObject:obj]) {
        return [LSUtil _serializeToJSON:obj];
    } else {
        // To avoid reinventing encoding logic, reuse NSJSONSerialization
        // for basic value-types via a temporary dictionary and slicing out the
        // encoded substring.
        //
        // Due to the nature of JSON and the assumption that NSJSONSerialization
        // will *not* inject unnecessary whitespace, the position of the encoded
        // object is fixed.
        NSString* output = [LSUtil _serializeToJSON:@{@"V":obj}];
        if (output == nil) {
            return output;
        }
        if ([output length] < 6) {
            NSLog(@"NSJSONSerialization generated invalid JSON: %@", output);
        }
        NSString* trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![trimmed hasPrefix:@"{\"V\":"] || ![trimmed hasSuffix:@"}"]) {
            NSLog(@"Unexpected JSON encoding: %@", output);
            return nil;
        }
        return [output substringWithRange:NSMakeRange(5, [output length] - 6)];
    }
}

+ (NSString*)_serializeToJSON:(id)dict {
    NSError* error;
    NSData* jsonData;
    @try {
        jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
    } @catch (NSException* e) {
        NSLog(@"Invalid object for JSON conversation");
        return nil;
    }
    if (!jsonData) {
        NSLog(@"Could not encode JSON: %@", error);
        return nil;
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

+ (NSMutableArray*)keyValueArrayFromDictionary:(NSDictionary<NSString*, NSObject*>*)dict {
    NSMutableArray* rval = [NSMutableArray arrayWithCapacity:dict.count];
    for (NSString* key in dict) {
        NSObject* val = dict[key];
        [rval addObject:@{@"Key": key,
                          @"Value": ([val isKindOfClass:[NSString class]]
                                     ? val
                                     : val.description)}];
    }
    return rval;
}

@end

@implementation NSDate(LSSpan)
- (int64_t) toMicros {
    return (int64_t)([self timeIntervalSince1970] * USEC_PER_SEC);
}
@end


