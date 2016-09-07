//
//  AppDelegate.m
//  LightStepTestUI
//

#import "AppDelegate.h"
#import "OTGlobal.h"
#import "LSTracer.h"

#import <GRPCClient/GRPCCall+ChannelArg.h>
#import <GRPCClient/GRPCCall+Tests.h>
#import <lightstep/Collector.pbrpc.h>

@interface AppDelegate ()

@end

@implementation AppDelegate

static NSString* kHostAddress = @"localhost:9997";

- (void)makeSomeGRPCRequest {
    // TODO: remove this. Just making sure that everything builds and links.
    [GRPCCall useInsecureConnectionsForHost:kHostAddress];
    [GRPCCall setUserAgentPrefix:@"HelloWorld/1.0" forHost:kHostAddress];
    
    LTSCollectorService *client = [[LTSCollectorService alloc] initWithHost:kHostAddress];
    
    LTSReportRequest *req = [LTSReportRequest message];
    req.auth = [[LTSAuth alloc] init];
    req.auth.accessToken = @"{your_access_token}";
    
    [client reportWithRequest:req handler:^(LTSReportResponse * _Nullable response, NSError * _Nullable error) {
        NSLog(@"RESPONSE: %@, ERROR: %@", response, error);
    }];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    LSTracer* tracer = [[LSTracer alloc] initWithToken:@"{your_access_token}" componentName:@"LightStepTestUI" flushIntervalSeconds:2];
    tracer.maxLogRecords = 600;
    tracer.maxSpanRecords = 600;

    [OTGlobal initSharedTracer:tracer];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
