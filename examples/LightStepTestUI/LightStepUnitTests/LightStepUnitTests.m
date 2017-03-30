#import <XCTest/XCTest.h>

#import <lightstep/LSSpan.h>
#import <lightstep/LSSpanContext.h>
#import <lightstep/LSTracer.h>
#import <lightstep/LSUtil.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kMaxLength = 8192;

@interface LightStepUnitTests : XCTestCase
@property(nonatomic, strong) LSTracer *tracer;
@end

@implementation LightStepUnitTests

- (void)setUp {
    [super setUp];
    self.tracer = [[LSTracer alloc] initWithToken:@"TEST_TOKEN"
                                    componentName:@"LightStepUnitTests"
                                          baseURL:[NSURL URLWithString:@"http://localhost:9997"]
                             flushIntervalSeconds:0]; // disable the flush loop
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
    NSDictionary *dict = @{ @"string": @"test", @"integer": @42, @"float": @3.14 };
    XCTAssertEqualObjects([LSUtil objectToJSONString:dict maxLength:kMaxLength],
                          @"{\"string\":\"test\",\"integer\":42,\"float\":3.14}");
}

- (void)testObjectToJSONStringItsComplicated {
    // NSDictionary with non-string keys.
    //
    // NOTE: only string keys are supported by NSJSONSerialization. Eventually,
    // it would be nice to be more flexible rather than having 'nil' be the
    // expected, silent encoding.
    NSDictionary *numKeys = @{ @1: @"one" };
    XCTAssertEqualObjects([LSUtil objectToJSONString:numKeys maxLength:kMaxLength], nil);
}

- (void)testPayloadMaxLength {
    NSString *longString = [@"" stringByPaddingToLength:400 withString:@"*" startingAtIndex:0];
    NSString *longStringJSON = [NSString stringWithFormat:@"\"%@\"", longString];

    XCTAssertEqualObjects([LSUtil objectToJSONString:longString maxLength:4000], longStringJSON);
    XCTAssertEqualObjects([LSUtil objectToJSONString:longString maxLength:100], nil);
    XCTAssertEqualObjects([LSUtil objectToJSONString:longString maxLength:400], nil);
    XCTAssertEqualObjects([LSUtil objectToJSONString:longString maxLength:402], longStringJSON);
}

- (void)testLSSpan {
    // Test timestamps, span context basics, and operation names.
    LSSpan *parent = (LSSpan *)[self.tracer startSpan:@"parent"];
    NSDate *parentFinish = [NSDate date];
    NSDictionary *parentJSON = [parent _toJSONWithFinishTime:parentFinish];
    {
        XCTAssertNotNil(parentJSON[@"span_guid"]);
        XCTAssertNotNil(parentJSON[@"trace_guid"]);
        XCTAssertNotEqual(parentJSON[@"span_guid"], @(0));
        XCTAssertNotEqual(parentJSON[@"trace_guid"], @(0));
        XCTAssertEqual(parentJSON[@"oldest_micros"], @([parent.startTime toMicros]));
        XCTAssertEqual(parentJSON[@"youngest_micros"], @([parentFinish toMicros]));
        XCTAssertEqual(parentJSON[@"span_name"], @"parent");
    }

    // Additionally test span context inheritance, tags, and logs.
    id<OTSpanContext> parentContext = (id<OTSpanContext>)parent.context; // wtf clang
    id<OTSpan> child = [self.tracer startSpan:@"child"
                                      childOf:parentContext
                                         tags:@{
                                             @"string": @"abc",
                                             @"int": @(42),
                                             @"bool": @(true)
                                         }];
    NSDate *logTime = [NSDate date];
    [child log:@"log1" timestamp:logTime payload:@{ @"foo": @"bar" }];
    [child logEvent:@"log2"];
    [child log:@{ @"foo": @(42), @"bar": @"baz" }];
    [child log:@{ @"event": @(42), @"bar": @"baz" }]; // the "event" field name gets special treatment
    {
        NSDate *childFinish = [NSDate date];
        NSDictionary *childJSON = [(LSSpan *)child _toJSONWithFinishTime:childFinish];

        XCTAssert([childJSON[@"trace_guid"] isEqualToString:parentJSON[@"trace_guid"]]);
        XCTAssertNotEqual(childJSON[@"span_guid"], @(0));
        NSArray *childTags = childJSON[@"attributes"];
        XCTAssertEqual(childTags.count, 4);
        for (NSDictionary *keyValuePair in childTags) {
            NSString *tagKey = keyValuePair[@"Key"];
            NSString *tagVal = keyValuePair[@"Value"];
            if ([tagKey isEqualToString:@"string"]) {
                XCTAssert([tagVal isEqualToString:@"abc"]);
            } else if ([tagKey isEqualToString:@"int"]) {
                XCTAssert([tagVal isEqualToString:@"42"]);
            } else if ([tagKey isEqualToString:@"bool"]) {
                XCTAssert([tagVal isEqualToString:@"1"]); // no real NSBoolean* type :(
            } else if ([tagKey isEqualToString:@"parent_span_guid"]) {
                XCTAssert([tagVal isEqualToString:parentJSON[@"span_guid"]]);
            } else {
                XCTAssert(FALSE); // kv.key is not an expected value
            }
        }

        NSArray<NSDictionary *> *childLogs = childJSON[@"log_records"];
        XCTAssertEqual(childLogs.count, 4);
        {
            // Check explicit timestamps.
            XCTAssertEqual(childLogs[0][@"timestamp_micros"], @(logTime.toMicros));
            // Check that `event` is populated properly.
            [self assertLogKV:childLogs[0] key:@"event" value:@"log1"];
            // Among other things, "event" is excluded from the payload_json.
            [self assertLogKV:childLogs[0] key:@"payload_json" value:@"{\"foo\":\"bar\"}"];
        }
        {
            // Check that `event` is populated properly.
            [self assertLogKV:childLogs[1] key:@"event" value:@"log2"];
            // There should be no payload.
            [self assertLogKV:childLogs[1] key:@"payload_json" value:nil];
        }

        {
            // There should be no `event` or `payload_json`:
            [self assertLogKV:childLogs[2] key:@"event" value:nil];
            [self assertLogKV:childLogs[2] key:@"payload_json" value:nil];
            [self assertLogKV:childLogs[2] key:@"foo" value:@"42"];
            [self assertLogKV:childLogs[2] key:@"bar" value:@"baz"];
        }
        {
            [self assertLogKV:childLogs[3] key:@"event" value:@"42"];
            [self assertLogKV:childLogs[3] key:@"bar" value:@"baz"];
        }
    }
}

- (void)assertLogKV:(NSDictionary *)logStruct key:(NSString *)key value:(NSString *_Nullable)value {
    for (NSDictionary *keyValuePair in logStruct[@"fields"]) {
        if ([keyValuePair[@"Key"] isEqualToString:key]) {
            XCTAssert([keyValuePair[@"Value"] isEqualToString:value]);
            return;
        }
    }
    XCTAssertNil(value);
}

- (void)testBaggage {
    // Test timestamps, span context basics, and operation names.
    id<OTSpan> parent = [self.tracer startSpan:@"parent"];
    [parent setBaggageItem:@"suitcase" value:@"brown"];
    id<OTSpan> child1 = [self.tracer startSpan:@"child" childOf:parent.context];
    [parent setBaggageItem:@"backpack" value:@"gray"];
    id<OTSpan> child2 = [self.tracer startSpan:@"child" childOf:parent.context];
    XCTAssert([[child1 getBaggageItem:@"suitcase"] isEqualToString:@"brown"]);
    XCTAssertNil([child1 getBaggageItem:@"backpack"]);
    XCTAssert([[child2 getBaggageItem:@"suitcase"] isEqualToString:@"brown"]);
    XCTAssert([[child2 getBaggageItem:@"backpack"] isEqualToString:@"gray"]);
}

- (void)testSpanContextBinarySerialization {
    NSDictionary *testBaggage = @{
                                  @"checked": @"baggage",
                                  @"backpack": @"gray",
                                  @"suitcase": @"brown",
                                  };
    LSSpanContext *ctx = [[LSSpanContext alloc] initWithTraceId:123 spanId:456 baggage:testBaggage];
    NSData *protoEnc = [ctx asEncodedProtobufMessage];

    LSSpanContext *decode = [LSSpanContext decodeFromProtobufMessage:protoEnc error:nil];

    XCTAssertNotNil(decode);
    XCTAssertEqual(ctx.traceId, decode.traceId);
    XCTAssertEqual(ctx.spanId, decode.spanId);
    XCTAssertEqual(ctx.baggage.count, decode.baggage.count);

    XCTAssert([ctx.baggage[@"checked"] isEqualToString:decode.baggage[@"checked"]]);
    XCTAssert([ctx.baggage[@"suitcase"] isEqualToString:decode.baggage[@"suitcase"]]);
    XCTAssert([ctx.baggage[@"backpack"] isEqualToString:decode.baggage[@"backpack"]]);
}

- (void)testLSBinaryCarrier {
    // Encode and decode, assert equality of spans.
    id<OTSpan> span = [self.tracer startSpan:@"Sending Request"];
    [span setBaggageItem:@"checked" value:@"baggage"];
    [span setBaggageItem:@"backpack" value:@"gray"];
    [span setBaggageItem:@"suitcase" value:@"brown"];

    NSMutableData *data = [[NSMutableData alloc] init];
    [self.tracer inject:span.context format:OTFormatBinary carrier:data];
    id<OTSpanContext> ctx = [self.tracer extractWithFormat:OTFormatBinary carrier:data];

    LSSpanContext *c = (LSSpanContext *)ctx;
    LSSpanContext *s = (LSSpanContext *)span.context;
    XCTAssertEqual(c.traceId, s.traceId);
    XCTAssertEqual(c.spanId, s.spanId);
    XCTAssertEqual(c.baggage.count, s.baggage.count);

    XCTAssert([c.baggage[@"checked"] isEqualToString:s.baggage[@"checked"]]);
    XCTAssert([c.baggage[@"suitcase"] isEqualToString:s.baggage[@"suitcase"]]);
    XCTAssert([c.baggage[@"backpack"] isEqualToString:s.baggage[@"backpack"]]);
}

- (void)testLSBinaryExtraction {
    // Take a known piece of base64-encoded data and assert
    NSString *base64 = @"EigJOjioEaYHBgcRNmifUO7/xlgYASISCgdjaGVja2VkEgdiYWdnYWdl";
    NSData *encoded = [base64 dataUsingEncoding:NSUTF8StringEncoding];

    LSSpanContext *ctx = (LSSpanContext *)[self.tracer extractWithFormat:OTFormatBinary carrier:encoded];
    XCTAssertEqual(ctx.spanId, 6397081719746291766);
    XCTAssertEqual(ctx.traceId, 506100417967962170);
    XCTAssertEqual(ctx.baggage.count, 1);

    XCTAssert([ctx.baggage[@"checked"] isEqualToString:@"baggage"]);
}

@end

NS_ASSUME_NONNULL_END
