//
//  ViewController.swift
//  MercurialPaint
//
//  Created by Simon Gladman on 04/12/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//

import UIKit

class ViewController: UIViewController
{

    let mercurialPaint = MercurialPaint(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024), device: MTLCreateSystemDefaultDevice())
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.blackColor()
       
        view.addSubview(mercurialPaint)
    }

}

