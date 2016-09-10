#import <XCTest/XCTest.h>

#import <lightstep/LSSpan.h>
#import <lightstep/LSTracer.h>
#import <lightstep/LSUtil.h>
#import <lightstep/Collector.pbobjc.h>

const NSUInteger kMaxLength = 8192;

@interface LightStepUnitTests : XCTestCase

@end

@implementation LightStepUnitTests {
    LSTracer *m_tracer;
}

- (void)setUp {
    [super setUp];
    m_tracer = [[LSTracer alloc] initWithToken:@"TEST_TOKEN"
                                 componentName:@"LightStepUnitTests"
                                      hostport:@"localhost:9997"
                          flushIntervalSeconds:0  // disable the flush loop
                                  insecureGRPC:true];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testObjectToJSONStringBasics {
    // Null
    XCTAssertEqualObjects([LSUtil objectToJSONString:nil maxLength:kMaxLength], nil);
    // Empty string
    XCTAssertEqualObjects([LSUtil objectToJSONString:@"" maxLength:kMaxLength], @"\"\"");
    // Regular string
    XCTAssertEqualObjects([LSUtil objectToJSONString:@"test" maxLength:kMaxLength], @"\"test\"");
    // String that happens to be a number
    XCTAssertEqualObjects([LSUtil objectToJSONString:@"42" maxLength:kMaxLength], @"\"42\"");
    // Integer
    XCTAssertEqualObjects([LSUtil objectToJSONString:@42 maxLength:kMaxLength], @"42");
    // Float
    XCTAssertEqualObjects([LSUtil objectToJSONString:@3.14 maxLength:kMaxLength], @"3.14");
    // Empty array
    XCTAssertEqualObjects([LSUtil objectToJSONString:@[] maxLength:kMaxLength], @"[]");
    // Regular array
    NSArray *arr = @[@"test", @42, @3.14];
    XCTAssertEqualObjects([LSUtil objectToJSONString:arr maxLength:kMaxLength], @"[\"test\",42,3.14]");
    // Empty dictionary
    XCTAssertEqualObjects([LSUtil objectToJSONString:@{} maxLength:kMaxLength], @"{}");
    // Simple dictionary
    // TODO: this test is a little fragile since there aren't encoding order
    // guarentees for dictionaries.
    NSDictionary* dict = @{@"string": @"test",
                           @"integer": @42,
                           @"float": @3.14};
    XCTAssertEqualObjects([LSUtil objectToJSONString:dict maxLength:kMaxLength], @"{\"string\":\"test\",\"integer\":42,\"float\":3.14}");
}

- (void)testObjectToJSONStringItsComplicated {
    // NSDictionary with non-string keys.
    //
    // NOTE: only string keys are supported by NSJSONSerialization. Eventually,
    // it would be nice to be more flexible rather than having 'nil' be the
    // expected, silent encoding.
    NSDictionary* numKeys = @{@1:@"one"};
    XCTAssertEqualObjects([LSUtil objectToJSONString:numKeys maxLength:kMaxLength], nil);
}

- (void)testPayloadMaxLength {
    NSString* longString = [@"" stringByPaddingToLength:400 withString:@"*" startingAtIndex:0];
    NSString* longStringJSON = [NSString stringWithFormat:@"\"%@\"", longString];

    XCTAssertEqualObjects([LSUtil objectToJSONString:longString maxLength:4000], longStringJSON);
    XCTAssertEqualObjects([LSUtil objectToJSONString:longString maxLength:100], nil);
    XCTAssertEqualObjects([LSUtil objectToJSONString:longString maxLength:400], nil);
    XCTAssertEqualObjects([LSUtil objectToJSONString:longString maxLength:402], longStringJSON);
}

- (void)testLSSpan {
    // Test timestamps, span context basics, and operation names.
    LSSpan* parent = [m_tracer startSpan:@"parent"];
    LSPBSpanContext* parentCtx;
    {
        NSDate* parentFinish = [NSDate date];
        LSPBSpan* spanProto = [parent _toProto:parentFinish];
        parentCtx = spanProto.spanContext;
        XCTAssertNotEqual(parentCtx.traceId, 0);
        XCTAssertNotEqual(parentCtx.spanId, 0);
        XCTAssertEqual(spanProto.startTimestamp.seconds, [parent._startTime toMicros] / 1000000);
        XCTAssertEqual(spanProto.durationMicros, [parentFinish toMicros] - [parent._startTime toMicros]);
        XCTAssertEqual(spanProto.operationName, @"parent");
    }
    
    // Additionally test span context inheritance, tags, and logs.
    LSSpan* child = [m_tracer startSpan:@"child" childOf:parent.context tags:@{@"string": @"abc", @"int": @(42), @"bool": @(true)}];
    NSDate* logTime = [NSDate date];
    [child log:@"log1" timestamp:logTime payload:@{@"foo": @"bar"}];
    [child logEvent:@"log2"];
    {
        NSDate* childFinish = [NSDate date];
        LSPBSpan* spanProto = [child _toProto:childFinish];
        XCTAssertEqual(spanProto.spanContext.traceId, parentCtx.traceId);
        XCTAssertNotEqual(spanProto.spanContext.spanId, 0);
        XCTAssertEqual(spanProto.referencesArray.count, 1);
        XCTAssertEqual([spanProto.referencesArray objectAtIndex:0].spanContext.traceId, spanProto.spanContext.traceId);
        XCTAssertEqual(spanProto.tagsArray.count, 3);
        for (LSPBKeyValue* kv in spanProto.tagsArray) {
            if ([kv.key isEqualToString:@"string"]) {
                XCTAssert([kv.stringValue isEqualToString:@"abc"]);
            } else if ([kv.key isEqualToString:@"int"]) {
                XCTAssertEqual(kv.intValue, 42);
            } else if ([kv.key isEqualToString:@"bool"]) {
                XCTAssertEqual(kv.intValue, 1);  // no real NSBoolean* type :(
            } else {
                XCTAssert(FALSE);  // kv.key is not an expected value
            }
        }
        XCTAssertEqual(spanProto.logsArray.count, 2);
        XCTAssert([[[spanProto.logsArray objectAtIndex:0].keyvaluesArray objectAtIndex:0].key isEqualToString:@"event"]);
        XCTAssert([[[spanProto.logsArray objectAtIndex:0].keyvaluesArray objectAtIndex:0].stringValue isEqualToString:@"log1"]);
        XCTAssert([[[spanProto.logsArray objectAtIndex:0].keyvaluesArray objectAtIndex:1].key isEqualToString:@"payload_json"]);
        XCTAssert([[[spanProto.logsArray objectAtIndex:0].keyvaluesArray objectAtIndex:1].stringValue isEqualToString:@"{\"foo\":\"bar\"}"]);
        XCTAssertEqualObjects([spanProto.logsArray objectAtIndex:0].timestamp, [LSUtil protoTimestampFromDate:logTime]);
        XCTAssert([[[spanProto.logsArray objectAtIndex:1].keyvaluesArray objectAtIndex:0].key isEqualToString:@"event"]);
        XCTAssert([[[spanProto.logsArray objectAtIndex:1].keyvaluesArray objectAtIndex:0].stringValue isEqualToString:@"log2"]);
    }
}

- (void)testBaggage {
    // Test timestamps, span context basics, and operation names.
    LSSpan* parent = [m_tracer startSpan:@"parent"];
    [parent setBaggageItem:@"suitcase" value:@"brown"];
    LSSpan* child1 = [m_tracer startSpan:@"child" childOf:parent.context];
    [parent setBaggageItem:@"backpack" value:@"gray"];
    LSSpan* child2 = [m_tracer startSpan:@"child" childOf:parent.context];
    XCTAssert([[child1 getBaggageItem:@"suitcase"] isEqualToString:@"brown"]);
    XCTAssertNil([child1 getBaggageItem:@"backpack"]);
    XCTAssert([[child2 getBaggageItem:@"suitcase"] isEqualToString:@"brown"]);
    XCTAssert([[child2 getBaggageItem:@"backpack"] isEqualToString:@"gray"]);
}

@end
