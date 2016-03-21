//
//  ViewController.m
//  LightStepTestUI
//

#import "ViewController.h"
#import "LSTracer.h"

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
       parentSpan:(LSSpan*)parentSpan
    completionHandler:(void(^)(NSString*))completionHandler {

    NSString* url = [NSString stringWithFormat:@"https://api.github.com/users/%@", username];

    self.callbacksRemaining = 3;
    self->_completionHandler = completionHandler;

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
    self.callbacksRemaining--;
    if (error) {
        self.callbacksRemaining = 0;
        (self->_completionHandler)(error.localizedDescription);
    } else if (self.callbacksRemaining == 0) {
        (self->_completionHandler)([self _infoString]);
    }
}

/**
 * Calls the callback with either an NSArray* or NSDictionary* depending on the
 * JSON returned by the URL.
 */
- (void)_getHTTP:(LSSpan*)parentSpan
             url:(NSString*)urlString
completionHandler:(void (^)(id response, NSError *error))completionHandler {

    LSSpan* span = [[LSTracer sharedTracer] startSpan:@"NSURLRequest" parent:parentSpan];

    NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSMutableDictionary* headers = [NSMutableDictionary dictionaryWithDictionary:[config HTTPAdditionalHeaders]];
    [headers setObject:@"LightStep iOS Example" forKey:@"User-Agent"];
    config.HTTPAdditionalHeaders = headers;

    NSURL* url = [NSURL URLWithString:urlString];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                                       timeoutInterval:10];
    [request setHTTPMethod:@"GET"];

    NSURLSession* session = [NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask* task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                                id obj;
                                                if (error == nil) {

                                                    obj = [NSJSONSerialization JSONObjectWithData:data
                                                                                          options:NSJSONReadingMutableContainers
                                                                                            error:nil];
                                                    [span logEvent:@"response" payload:obj];
                                                } else {
                                                    [span logEvent:@"error" payload:error.localizedDescription];
                                                }
                                                completionHandler(obj, error);
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

    [output appendString:[NSString stringWithFormat:@"Public repositories: %lu\n", self.repoNames.count]];
    for (NSString* name in self.repoNames) {
        [output appendString:[NSString stringWithFormat:@"\t%@\n", name]];
    }
    [output appendString:[NSString stringWithFormat:@"Recent events: %ld\n", self.eventTotal]];
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
    LSSpan* span = [[LSTracer sharedTracer] startSpan:@"button_pressed"];

    self.resultsTextView.text = @"Starting query...";
    [[UserInfo new] queryInfo:self.usernameTextField.text
                   parentSpan:span
            completionHandler:^(NSString* text) {
                [span logEvent:@"query_complete"
                       payload:@{@"main_thread":@([NSThread isMainThread])}];
                NSString* displayString = [NSString stringWithFormat:@"%@\nView trace at:\n %@\n", text, [span _generateTraceURL]];

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
