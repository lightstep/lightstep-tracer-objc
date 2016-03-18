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

    LSSpan* span = [[LSTracer sharedTracer] startSpan:@"user_info"];

    NSString* username = self.usernameTextField.text;

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Querying GitHub"
                                                    message:username
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];

    [NSThread sleepForTimeInterval:.05];
    NSDictionary* user = [self _getHTTP];

    NSMutableString* output = [NSMutableString new];
    [output appendString:[NSString stringWithFormat:@"User: %@\n", user[@"login"]]];
    [output appendString:[NSString stringWithFormat:@"Type: %@\n", user[@"type"]]];

    NSLog(@"%@", output);

    [span finish];
}

- (NSDictionary*)_getHTTP {

    NSURL* url = [NSURL URLWithString:@"https://api.github.com/users/lightstep"];
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

    NSMutableDictionary *result = [NSJSONSerialization JSONObjectWithData:response
                                                             options:NSJSONReadingMutableContainers error:nil];
    return result;
}

@end
