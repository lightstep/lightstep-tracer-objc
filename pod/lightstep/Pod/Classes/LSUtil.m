#import "LSUtil.h"
#import <stdlib.h>  // arc4random_uniform()

@implementation LSUtil

+ (NSString*)generateGUID {
    return [NSString stringWithFormat:@"%x%x", arc4random(), arc4random()];
}

@end

@implementation NSDate(LSSpan)
- (int64_t) toMicros
{
    return (int64_t)([self timeIntervalSince1970] * USEC_PER_SEC);
}
@end