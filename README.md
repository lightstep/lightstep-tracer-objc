# lightstep-tracer-objc

[![Version](https://img.shields.io/cocoapods/v/lightstep.svg?style=flat)](http://cocoapods.org/pods/lightstep)
[![License](https://img.shields.io/cocoapods/l/lightstep.svg?style=flat)](http://cocoapods.org/pods/lightstep)
[![Platform](https://img.shields.io/cocoapods/p/lightstep.svg?style=flat)](http://cocoapods.org/pods/lightstep)

The LightStep distributed tracing library for Objective-C and Swift.

## Installation (CocoaPods)

1. Ensure you have [CocoaPods installed](https://guides.cocoapods.org/using/getting-started.html) (TL;DR: `sudo gem install cocoapods`)
2. Create a `Podfile` in your Xcode project and add the following line:

```ruby
pod 'lightstep', '~>2.0'
```

3. Run `pod install` in your project directory. Open the newly created workspace file in Xcode.

## Getting started

```objectivec
#import "LSTracer.h"
#import "OTGlobal.h"

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // Initialize the LightStep tracer implementation
    LSTracer* tracer = [[LSTracer alloc] initWithToken:@"{your_access_token}"];
    [OTGlobal initSharedTracer:tracer];

    // <Your normal initialization code here>

    return YES;
}

// Elsewhere:
- (void)someFunction:... {

    id<OTSpan> span = [[OTGlobal sharedTracer] startSpan:@"an operation name"];

    ...

    [span finish];
}
```

* For more info on OpenTracing, see [opentracing.io](http://opentracing.io).
