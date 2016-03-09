//
//  ViewController.m
//  LightStepTestUI
//

#import "ViewController.h"
#import "LSTracer.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *counterLabel;
@property int counter;
- (IBAction)incrementAction:(id)sender;
- (IBAction)decrementAction:(id)sender;
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

- (IBAction)decrementAction:(id)sender {
    LSSpan* span = [[LSTracer sharedInstance] startSpan:@"decrement_action"];
    self.counter--;
    [span logEvent:@"count_updated" payload:[NSNumber numberWithInt:self.counter]];
    [self.counterLabel setText:[NSString stringWithFormat:@"%d", self.counter]];
    [span finish];

    if (self.counter > 0 && self.counter % 5 == 0) {
        LSSpan* timerSpan = [[LSTracer sharedInstance] startSpan:@"timer_span"];
        [timerSpan logEvent:@"start" payload:[NSNumber numberWithInt:self.counter]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, self.counter * 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [timerSpan logEvent:@"end" payload:[NSNumber numberWithInt:self.counter]];
            [timerSpan finish];
        });
    }
}

- (IBAction)incrementAction:(id)sender {
    LSSpan* span = [[LSTracer sharedInstance] startSpan:@"increment_action"];
    self.counter++;
    [span logEvent:@"count_updated" payload:[NSNumber numberWithInt:self.counter]];
    [self.counterLabel setText:[NSString stringWithFormat:@"%d", self.counter]];

    if (self.counter % 7 == 4) {
        [span setOperationName:@"increment_action_with_payload"];
        [NSThread sleepForTimeInterval:.05];
        [span logEvent:@"payload_test" payload:@{@"one":@1,@"two":@"two",@"three":@[]}];
        [NSThread sleepForTimeInterval:.05];
    }

    [span finish];
}
@end
