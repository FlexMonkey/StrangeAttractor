//
//  ViewController.swift
//  StrangeAttractor
//
//  Created by Simon Gladman on 27/05/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import UIKit


extension CGRect {
    var minDim : CGFloat {
        return min(width, height)
    }
}

class ViewController: UIViewController {

    var strangeAttractorRenderer: StrangeAttractorRenderer!

    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        let side = view.frame.minDim
        
        strangeAttractorRenderer = StrangeAttractorRenderer(
            frame: CGRect(x: 0, y: 0, width: side, height: side),
            device: MTLCreateSystemDefaultDevice()!, 
            width: side,
            contentScaleFactor: UIScreen.main.scale)
        
        view.addSubview(strangeAttractorRenderer)
    }

    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        strangeAttractorRenderer.isPaused = false
    }

    override var prefersStatusBarHidden : Bool
    {
        return true
    }

    override func viewDidLayoutSubviews()
    {
        let side = view.frame.minDim
        
        strangeAttractorRenderer.frame = CGRect(
            x: (view.frame.width - side) / 2,
            y: (view.frame.height - side) / 2,
            width: side,
            height: side)
    }
}

