//
//  ViewController.swift
//  StrangeAttractor
//
//  Created by Simon Gladman on 27/05/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    let strangeAttractorRenderer = StrangeAttractorRenderer(
        frame: CGRect(x: 50, y: 50, width: 640, height: 640),
        device: nil)
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        view.addSubview(strangeAttractorRenderer)
        
        print("viewDidLoad")
    }

    
    override func viewDidAppear(animated: Bool)
    {
        super.viewDidAppear(animated)
        
        strangeAttractorRenderer.paused = false
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

