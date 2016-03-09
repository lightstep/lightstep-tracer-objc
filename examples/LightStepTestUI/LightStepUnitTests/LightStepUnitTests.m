#import <XCTest/XCTest.h>
#import "LSUtil.h"

const NSUInteger kMaxLength = 8192;

@interface LightStepUnitTests : XCTestCase

@end

@implementation LightStepUnitTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
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

@end
