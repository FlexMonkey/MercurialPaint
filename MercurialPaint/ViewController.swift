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

    let mercurialPaint = MercurialPaint(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let shadingImageEditor = ShadingImageEditor()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.blackColor()
       
        view.addSubview(mercurialPaint)
        view.addSubview(shadingImageEditor)
        
        shadingImageEditor.addTarget(self,
            action: "shadingImageChange",
            forControlEvents: UIControlEvents.ValueChanged)
    }

    func shadingImageChange()
    {
        mercurialPaint.shadingImage = shadingImageEditor.image
    }
    
    override func viewDidLayoutSubviews()
    {
        mercurialPaint.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        
        shadingImageEditor.frame = CGRect(x: view.frame.width - 300, y: 0, width: 300, height: view.frame.height)
    }
}

