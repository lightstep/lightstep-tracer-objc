//
//  LSSpanContext.h
//  LightStepTestUI
//
//  Created by Ben Sigelman on 7/21/16.
//  Copyright © 2016 LightStep. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "OTSpanContext.h"

@interface LSSpanContext : OTSpanContext

#pragma mark - OpenTracing API
- (void)setBaggageItem:(NSString*)key value:(NSString*)value;
- (NSString*)getBaggageItem:(NSString*)key;

@end
