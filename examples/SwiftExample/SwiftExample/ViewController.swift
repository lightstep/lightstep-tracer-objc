//
//  ViewController.swift
//  SwiftExample
//
//  Created by Ben Sigelman on 9/11/16.
//  Copyright © 2016 LightStep. All rights reserved.
//

import UIKit

import opentracing

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        let span = OTGlobal.sharedTracer().startSpan("foo");
        span.finish();
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

