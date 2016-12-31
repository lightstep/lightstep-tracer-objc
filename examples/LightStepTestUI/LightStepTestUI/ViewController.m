//
//  ViewController.m
//  LightStepTestUI
//

#import "ViewController.h"
#import "lightstep/LSTPTracer.h"
#import "opentracing/OTGlobal.h"

@interface UserInfo : NSObject {
    void (^_completionHandler)(NSString* text);
}
@property (strong, atomic) NSString* login;
@property (strong, atomic) NSString* type;
@property (strong, atomic) NSMutableArray* repoNames;
@property (atomic) NSUInteger eventTotal;
@property (strong, atomic) NSMutableDictionary* eventCount;

@property (atomic) NSInteger callbacksRemaining;
@end

@implementation UserInfo

/**
 * Standard init method.
 */
- (id)init {
    if (self = [super init]) {
        self.repoNames = [NSMutableArray new];
        self.eventCount = [NSMutableDictionary new];
    }
    return self;
}

/**
 * Given a username, makes multiples asynchronous queries to GitHub, collects
 * info about the user in this object, and finally calls the completion handler
 * when all queries are done.
 *
 * NOTE: this method is only safe to call once per UserInfo object in order to
 * keep the code simple.
 */
- (void)queryInfo:(NSString*)username
       parentSpan:(id<OTSpan>)parentSpan
    completionHandler:(void(^)(NSString*))completionHandler {

    NSString* url = [NSString stringWithFormat:@"https://api.github.com/users/%@", username];

    self.callbacksRemaining = 3;
    self->_completionHandler = completionHandler;

    // Set a timeout.  The code currently intentionally does not handle the case
    // missing usernames correctly and the timeout here will be hit; this is
    // useful for demonstrating an error trace.
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 8.0);
    dispatch_after(delay, dispatch_get_main_queue(), ^(void){
        if (self.callbacksRemaining > 0) {
            NSError* err = [NSError errorWithDomain:@"com.lightstep.example"
                                               code:408
                                           userInfo:@{NSLocalizedDescriptionKey:@"Something went wrong!"}];
            [self _queryInfoStep:err];
        }
    });

    [self _getHTTP:parentSpan url:url completionHandler:^(id resp, NSError* error) {
        self.login = resp[@"login"];
        self.type  = resp[@"type"];
        [self _queryInfoStep:error];

        [self _getHTTP:parentSpan url:resp[@"repos_url"] completionHandler:^(id repoList, NSError* error) {
            for (NSDictionary* repo in repoList) {
                [self.repoNames addObject:repo[@"name"]];
            }
            [self _queryInfoStep:error];
        }];

        [self _getHTTP:parentSpan url:resp[@"received_events_url"] completionHandler:^(id eventList, NSError* error) {
            for (NSDictionary* event in eventList) {
                NSString* key = event[@"type"];
                NSNumber* count = [self.eventCount objectForKey:key] ?: @0;
                [self.eventCount setObject:@([count intValue] + 1) forKey:key];
                self.eventTotal++;
            }
            [self _queryInfoStep:error];
        }];
    }];
}

/**
 * Called at the completion of each asynchronous API call. Calls the
 * completion callback on the first error or calls the completion callback with
 * the full user info onces it is available.
 */
- (void)_queryInfoStep:(NSError*)error {
    NSString* text;
    if (error != nil) {
        self.callbacksRemaining -= MAX(self.callbacksRemaining, 1);
        text = error.localizedDescription;
    } else {
        self.callbacksRemaining--;
        text = [self _infoString];
    }

    if (self.callbacksRemaining == 0) {
        (self->_completionHandler)(text);
    }
}

/**
 * Calls the callback with either an NSArray* or NSDictionary* depending on the
 * JSON returned by the URL.
 */
- (void)_getHTTP:(id<OTSpan>)parentSpan
             url:(NSString*)urlString
completionHandler:(void (^)(id response, NSError *error))completionHandler {

    // Rewrite the URL to use the LightStep proxy server
    NSString* gitHubPrefix = @"https://api.github.com/";
    NSString* urlPath = [urlString substringFromIndex:([gitHubPrefix length] - 1)];

    id<OTSpan> span = [[OTGlobal sharedTracer] startSpan:@"NSURLRequest" childOf:parentSpan.context];

    NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSMutableDictionary* headers = [NSMutableDictionary dictionaryWithDictionary:[config HTTPAdditionalHeaders]];
    [headers setObject:@"LightStep iOS Example" forKey:@"User-Agent"];
    [headers setObject:((LSTPTracer*)span.tracer).accessToken forKey:@"LightStep-Access-Token"];
    [[OTGlobal sharedTracer] inject:span.context format:OTFormatTextMap carrier:headers];
    config.HTTPAdditionalHeaders = headers;

    NSURLComponents* urlComponents = [NSURLComponents new];
    urlComponents.scheme = @"http";
    urlComponents.host = @"example-proxy.lightstep.com";
    urlComponents.port = @(80);
    urlComponents.path = urlPath;
    NSURL* url = [urlComponents URL];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                                       timeoutInterval:10];
    [request setHTTPMethod:@"GET"];

    NSURLSession* session = [NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask* task =
    [session dataTaskWithRequest:request
               completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                   id obj = nil;
                   if (error == nil) {
                       
                       obj = [NSJSONSerialization JSONObjectWithData:data
                                                             options:NSJSONReadingMutableContainers
                                                               error:nil];
                       [span logEvent:@"response" payload:obj];
                   } else {
                       [span logEvent:@"error" payload:error.localizedDescription];
                   }
                   
                   @try {
                       completionHandler(obj, error);
                   } @catch(NSException* exception) {
                       [span log:@"Exception in completion handler" timestamp:nil payload:exception];
                   }
                   [span finish];
               }];
    [task resume];
}

/**
 * Convert the colleted UserInfo to an NSString.
 */
- (NSString*)_infoString {
    NSMutableString* output = [NSMutableString new];
    [output appendString:[NSString stringWithFormat:@"User: %@\n", self.login]];
    [output appendString:[NSString stringWithFormat:@"Type: %@\n", self.type]];

    [output appendString:[NSString stringWithFormat:@"Public repositories: %@\n", @(self.repoNames.count)]];
    for (NSString* name in self.repoNames) {
        [output appendString:[NSString stringWithFormat:@"\t%@\n", name]];
    }
    [output appendString:[NSString stringWithFormat:@"Recent events: %@\n", @(self.eventTotal)]];
    for (NSString* key in self.eventCount) {
        [output appendString:[NSString stringWithFormat:@"\t%@: %@\n", key, self.eventCount[key]]];
    }
    return output;
}



@end

@interface ViewController ()
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)touchUpInsideGetInfo:(id)sender {
    // Hide the keyboard.
    [self.view endEditing:YES];

    id<OTSpan> span = [[OTGlobal sharedTracer] startSpan:@"button_pressed"];
    
    self.resultsTextView.text = @"Starting query...";
    [[UserInfo new] queryInfo:self.usernameTextField.text
                   parentSpan:span
            completionHandler:^(NSString* text) {
                [span logEvent:@"query_complete"
                       payload:@{@"main_thread":@([NSThread isMainThread])}];
                NSString* displayString = [NSString stringWithFormat:@"%@\n\nView trace at:\n %@\n", text, [(LSTPSpan*)span _generateTraceURL]];

                // UI updates need to occur in the main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    [span logEvent:@"ui_update"
                           payload:@{@"main_thread":@([NSThread isMainThread])}];
                    self.resultsTextView.text = displayString;
                    [span finish];
                });
            }
     ];
}

@end
