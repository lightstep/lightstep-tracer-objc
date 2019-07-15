//
//  AppDelegate.m
//  LightStepCocoaTestUI
//
//  Created by Austin Parker on 7/15/19.
//  Copyright © 2019 LightStep. All rights reserved.
//

#import "AppDelegate.h"
#import "lightstep/LSTracer.h"
#import "opentracing/OTGlobal.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    LSTracer* tracer = [[LSTracer alloc] initWithToken:@"TEST_TOKEN" componentName:@"LightStepCocoaTestUI" flushIntervalSeconds:2];
    tracer.maxSpanRecords = 600;
    
    [OTGlobal initSharedTracer:tracer];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
