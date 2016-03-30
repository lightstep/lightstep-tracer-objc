//
//  ViewController.swift
//  swifty
//
//  Created by Ben Sigelman on 3/29/16.
//  Copyright © 2016 LightStep. All rights reserved.
//

import opentracing

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Go through the motions of:
        //
        // 1) Initializing LightStep
        let rt = opentracing.OTGlobal.sharedTracer();
        
        // 2) Creating a test span
        let sp = rt.startSpan("parent string")
        
        // 3) Logging an event with a swifty key:value payload.
        sp.logEvent("event name", payload: ["key": 1234, "nested": [3, 4, 5, 6]])
        
        // 4) Creating a child span and set a LightStep join key.
        let child = rt.startSpan("child span", parent: sp)
        child.setTag("join:testkey", value: "testval");

        // 5) Make sure that TextMap injection works with an NSMutableDictionary.
        let carrier = NSMutableDictionary()
        rt.inject(child, format: opentracing.OTFormatTextMap, carrier: carrier)
        child.logEvent("meta-log of injected TextMap contents", payload:carrier)
        
        // 6) Finish both of the spans
        child.finish()
        sp.finish()
    }

}
