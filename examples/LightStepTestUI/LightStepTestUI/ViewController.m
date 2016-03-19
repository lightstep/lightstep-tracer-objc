//
//  ViewController.m
//  LightStepTestUI
//

#import "ViewController.h"
#import "LSTracer.h"

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

    NSString* username = self.usernameTextField.text;
    NSString* url = [NSString stringWithFormat:@"https://api.github.com/users/%@", username];
    NSDictionary* user = [self _getHTTP:span url:url];

    NSMutableString* output = [NSMutableString new];
    [output appendString:[NSString stringWithFormat:@"User: %@\n", user[@"login"]]];
    [output appendString:[NSString stringWithFormat:@"Type: %@\n", user[@"type"]]];

    NSArray* repoList = [self _getHTTP:span url:user[@"repos_url"]];
    [output appendString:[NSString stringWithFormat:@"Public repositories: %lu\n", repoList.count]];
    for (NSDictionary* repo in repoList) {
        [output appendString:[NSString stringWithFormat:@"\t%@\n", repo[@"name"]]];
    }

    int eventTotal = 0;
    NSArray* eventList = [self _getHTTP:span url:user[@"received_events_url"]];
    NSMutableDictionary* eventCount = [NSMutableDictionary new];
    for (NSDictionary* event in eventList) {
        NSString* key = event[@"type"];
        NSNumber* count = [eventCount objectForKey:key] ?: @0;
        [eventCount setObject:@([count intValue] + 1) forKey:key];
        eventTotal++;
    }
    [output appendString:[NSString stringWithFormat:@"Recent events: %d\n", eventTotal]];
    for (NSString* key in eventCount) {
        [output appendString:[NSString stringWithFormat:@"\t%@: %@\n", key, eventCount[key]]];
    }

    self.resultsTextView.text = output;
    [span finish];
}

/*
 * Returns either an NSArray* or NSDictionary* depending on the JSON returned
 * by the URL
 */
- (id)_getHTTP:(LSSpan*)parentSpan
           url:(NSString*)urlString {

    LSSpan* span = [[LSTracer sharedTracer] startSpan:@"NSURLRequest" parent:parentSpan];

    NSURL* url = [NSURL URLWithString:urlString];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                                       timeoutInterval:10];
    [request setHTTPMethod: @"GET"];

    NSMutableDictionary* headers = [NSMutableDictionary dictionaryWithDictionary:[request allHTTPHeaderFields]];
    [headers setObject:@"LightStep iOS Example" forKey:@"User-Agent"];
    request.allHTTPHeaderFields = headers;

    NSError *requestError = nil;
    NSURLResponse *urlResponse = nil;
    NSData *response = [NSURLConnection sendSynchronousRequest:request
                                              returningResponse:&urlResponse
                                                          error:&requestError];
    NSString *jsonString = [[NSString alloc] initWithData:response
                                                 encoding:NSUTF8StringEncoding];

    id obj = [NSJSONSerialization JSONObjectWithData:response
                                             options:NSJSONReadingMutableContainers
                                               error:nil];
    [span finish];
    return obj;
}

@end
