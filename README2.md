# LightStep iOS

[![Version](https://img.shields.io/cocoapods/v/lightstep.svg?style=flat)](http://cocoapods.org/pods/lightstep)
[![License](https://img.shields.io/cocoapods/l/lightstep.svg?style=flat)](http://cocoapods.org/pods/lightstep)
[![Platform](https://img.shields.io/cocoapods/p/lightstep.svg?style=flat)](http://cocoapods.org/pods/lightstep)

The LightStep implementation of the [OpenTracing API](http://opentracing.io/) for iOS.

*Note: OpenTracing does not yet have a iOS library. The LightStep implementation mirrors the OpenTracing API signatures so it can be used directly.*

## Installation (CocoaPods)

1. Ensure you have [cocoapods installed](https://guides.cocoapods.org/using/getting-started.html) (TL;DR: `sudo gem install cocoapods`)
2. Create a `Podfile` in your Xcode project and add the following line:

```ruby
pod "lightstep"
```

3. Run `pod install` in your project directory. Open the newly created workspace file in Xcode.

## Getting Started

```ios
#import "LSTracer.h"

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // Initialize the LightStep tracer implementation
    [LSTracer initGlobalTracer:@"{your_access_token}"];

    // <Your normal initialization code here>

    return YES;
}
```

* For more info on OpenTracing, see [opentracing.io](http://opentracing.io).
