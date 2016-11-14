#import <XCTest/XCTest.h>

#import <lightstep/LSSpan.h>
#import <lightstep/LSTracer.h>
#import <lightstep/LSUtil.h>

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
                                     plaintext:true];
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
    LSSpan* parent = (LSSpan*)[m_tracer startSpan:@"parent"];
    NSDictionary* parentJSON;
    {
        NSDate* parentFinish = [NSDate date];
        parentJSON = [parent _toJSON:parentFinish];
        XCTAssertNotNil(parentJSON[@"span_guid"]);
        XCTAssertNotNil(parentJSON[@"trace_guid"]);
        XCTAssertNotEqual(parentJSON[@"span_guid"], @(0));
        XCTAssertNotEqual(parentJSON[@"trace_guid"], @(0));
        XCTAssertEqual(parentJSON[@"oldest_micros"], @([parent._startTime toMicros]));
        XCTAssertEqual(parentJSON[@"youngest_micros"], @([parentFinish toMicros]));
        XCTAssertEqual(parentJSON[@"span_name"], @"parent");
    }

    // Additionally test span context inheritance, tags, and logs.
    LSSpan* child = (LSSpan*)[m_tracer startSpan:@"child" childOf:parent.context tags:@{@"string": @"abc", @"int": @(42), @"bool": @(true)}];
    NSDate* logTime = [NSDate date];
    [child log:@"log1" timestamp:logTime payload:@{@"foo": @"bar"}];
    [child logEvent:@"log2"];
    [child log:@{@"foo": @(42), @"bar": @"baz"}];
    [child log:@{@"event": @(42), @"bar": @"baz"}];  // the "event" field name gets special treatment
    {
        NSDate* childFinish = [NSDate date];
        NSDictionary* childJSON = [child _toJSON:childFinish];

        XCTAssert([childJSON[@"trace_guid"] isEqualToString:parentJSON[@"trace_guid"]]);
        XCTAssertNotEqual(childJSON[@"span_guid"], @(0));
        NSArray* childTags = childJSON[@"attributes"];
        XCTAssertEqual(childTags.count, 4);
        for (NSDictionary* keyValuePair in childTags) {
            NSString* tagKey = keyValuePair[@"Key"];
            NSString* tagVal = keyValuePair[@"Value"];
            if ([tagKey isEqualToString:@"string"]) {
                XCTAssert([tagVal isEqualToString:@"abc"]);
            } else if ([tagKey isEqualToString:@"int"]) {
                XCTAssert([tagVal isEqualToString:@"42"]);
            } else if ([tagKey isEqualToString:@"bool"]) {
                XCTAssert([tagVal isEqualToString:@"1"]);  // no real NSBoolean* type :(
            } else if ([tagKey isEqualToString:@"parent_span_guid"]) {
                XCTAssert([tagVal isEqualToString:parentJSON[@"span_guid"]]);
            } else {
                XCTAssert(FALSE);  // kv.key is not an expected value
            }
        }

        NSArray<NSDictionary*>* childLogs = childJSON[@"log_records"];
        XCTAssertEqual(childLogs.count, 4);
        {
            // Check explicit timestamps.
            XCTAssertEqual(childLogs[0][@"timestamp_micros"], @(logTime.toMicros));
            // Check that stable_name is populated properly.
            XCTAssert([childLogs[0][@"stable_name"] isEqualToString:@"log1"]);
            // Among other things, "event" is excluded from the payload_json.
            XCTAssert([childLogs[0][@"payload_json"] isEqualToString:@"{\"foo\":\"bar\"}"]);
        }
        {
            // Check that stable_name is populated properly.
            XCTAssert([childLogs[1][@"stable_name"] isEqualToString:@"log2"]);
            // There should be no payload.
            XCTAssertNil(childLogs[1][@"payload_json"]);
        }
        {
            // Check that stable_name is absent.
            XCTAssertNil(childLogs[2][@"stable_name"]);
            XCTAssert([childLogs[2][@"payload_json"] isEqualToString:@"{\"foo\":42,\"bar\":\"baz\"}"]);
        }
        {
            // Check that stable_name is converted to a string.
            XCTAssert([childLogs[3][@"stable_name"] isEqualToString:@"42"]);
            XCTAssert([childLogs[3][@"payload_json"] isEqualToString:@"{\"bar\":\"baz\"}"]);
        }
    }
}

- (void)testBaggage {
    // Test timestamps, span context basics, and operation names.
    LSSpan* parent = (LSSpan*)[m_tracer startSpan:@"parent"];
    [parent setBaggageItem:@"suitcase" value:@"brown"];
    LSSpan* child1 = (LSSpan*)[m_tracer startSpan:@"child" childOf:parent.context];
    [parent setBaggageItem:@"backpack" value:@"gray"];
    LSSpan* child2 = (LSSpan*)[m_tracer startSpan:@"child" childOf:parent.context];
    XCTAssert([[child1 getBaggageItem:@"suitcase"] isEqualToString:@"brown"]);
    XCTAssertNil([child1 getBaggageItem:@"backpack"]);
    XCTAssert([[child2 getBaggageItem:@"suitcase"] isEqualToString:@"brown"]);
    XCTAssert([[child2 getBaggageItem:@"backpack"] isEqualToString:@"gray"]);
}

@end
