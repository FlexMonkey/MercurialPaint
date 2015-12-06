//
//  SupportClasses.swift
//  MercurialText
//
//  Created by Simon Gladman on 30/11/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//

import SceneKit

class ParameterGroup
{
    init(name: String, parameters: [Parameter])
    {
        self.name = name
        self.parameters = parameters
    }
    
    let name: String
    let parameters: [Parameter]
}

class Parameter
{
    init(name: String, parameterFunction: ParameterFunction, value: CGFloat, minMax: MinMax)
    {
        self.name = name
        self.parameterFunction = parameterFunction
        self.value = value
        self.minMax = minMax
    }
    
    let name: String
    let parameterFunction: ParameterFunction
    var value: CGFloat
    let minMax: MinMax
}

enum ParameterFunction
{
    case AdjustLightPosition(index: Int, axis: PositionAxis)
    case AdjustLightHue(index: Int)
    case AdjustLightBrightness(index: Int)
    case AdjustMaterialShininess
}

enum PositionAxis
{
    case X
    case Y
    case Z
}

typealias MinMax = (min: Float, max: Float)

let MinMaxNorm = MinMax(min: 0, max: 1)
let MinMaxXY = MinMax(min: -50, max: 50)
let MinMaxZ = MinMax(min: -10, max: 50)

class OmniLight: SCNNode
{
    init(x: Float = 0, y: Float = 0, z: Float = 0, hue: CGFloat = 0, brightness: CGFloat = 0)
    {
        self.x = x
        self.y = y
        self.z = z
        
        self.hue = hue
        self.brightness = brightness
        
        super.init()
        
        let omniLight = SCNLight()
        omniLight.type = SCNLightTypeOmni
        
        light = omniLight
        
        position = SCNVector3(x: x, y: y, z: z)
        
        updateLightColor()
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    let x: Float
    let y: Float
    let z: Float
    
    var hue: CGFloat
        {
        didSet
        {
            updateLightColor()
        }
    }
    
    var brightness: CGFloat
        {
        didSet
        {
            updateLightColor()
        }
    }
    
    func updateLightColor()
    {
        light?.color = UIColor(hue: hue,
            saturation: 1,
            brightness: brightness,
            alpha: 1)
    }
}