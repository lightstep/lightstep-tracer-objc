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

    [span finish];
}
@end
