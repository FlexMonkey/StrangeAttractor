//
//  ViewController.swift
//  StrangeAttractor
//
//  Created by Simon Gladman on 27/05/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var strangeAttractorRenderer: StrangeAttractorRenderer!

    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.blackColor()
        
        let side = min(view.frame.width, view.frame.height)
        
        strangeAttractorRenderer = StrangeAttractorRenderer(
            frame: CGRect(x: 0, y: 0, width: side, height: side),
            device: MTLCreateSystemDefaultDevice()!, 
            width: side,
            contentScaleFactor: UIScreen.mainScreen().scale)
        
        view.addSubview(strangeAttractorRenderer)
    }

    
    override func viewDidAppear(animated: Bool)
    {
        super.viewDidAppear(animated)
        
        strangeAttractorRenderer.paused = false
    }

    override func prefersStatusBarHidden() -> Bool
    {
        return true
    }

    override func viewDidLayoutSubviews()
    {
        let side = min(view.frame.width, view.frame.height)
        
        strangeAttractorRenderer.frame = CGRect(
            x: (view.frame.width - side) / 2,
            y: (view.frame.height - side) / 2,
            width: side,
            height: side)
    }
}

