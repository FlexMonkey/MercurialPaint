//
//  MercurialPaint.swift
//  MercurialPaint
//
//  Created by Simon Gladman on 04/12/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//

import UIKit
import MetalKit
import MetalPerformanceShaders

class MercurialPaint: MTKView
{
    // MARK: Constants
    
    let particleCount: Int = 1024
    let alignment:Int = 0x4000
    let particlesMemoryByteSize:Int = 1024 * sizeof(Int)
    
    // MARK: Priavte variables
    
    private var threadsPerThreadgroup:MTLSize!
    private var threadgroupsPerGrid:MTLSize!
    
    private var particlesMemory:UnsafeMutablePointer<Void> = nil
    private var particlesVoidPtr: COpaquePointer!
    private var particlesParticlePtr: UnsafeMutablePointer<Int>!
    private var particlesParticleBufferPtr: UnsafeMutableBufferPointer<Int>!
    
    private var particlesBufferNoCopy: MTLBuffer!
    
    private var touchLocation = CGPoint(x: -1, y: -1)
    
    // MARK: Lazy variables
    
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(MTLPixelFormat.RGBA8Unorm,
        width: 1024,
        height: 1024,
        mipmapped: false)
    
    lazy var paintingTexture: MTLTexture =
    {
        [unowned self] in

        return self.device!.newTextureWithDescriptor(self.textureDescriptor)
    }()
    
    lazy var intermediateTexture: MTLTexture =
    {
        [unowned self] in
        
        return self.device!.newTextureWithDescriptor(self.textureDescriptor)
        }()
    
    lazy var paintingShaderPipelineState: MTLComputePipelineState =
    {
       [unowned self] in
        
        do
        {
            let library = self.device!.newDefaultLibrary()!
            
            let kernelFunction = library.newFunctionWithName("mercurialPaintShader")
            let pipelineState = try self.device!.newComputePipelineStateWithFunction(kernelFunction!)
            
            return pipelineState
        }
        catch
        {
            fatalError("Unable to create censusTransformMonoPipelineState")
        }
    }()
    
    lazy var commandQueue: MTLCommandQueue =
    {
       [unowned self] in
        
        return self.device!.newCommandQueue()
    }()
    
    lazy var blur: MPSImageGaussianBlur =
    {
        [unowned self] in
        
        return MPSImageGaussianBlur(device: self.device!, sigma: 6)
        }()
    
    lazy var threshold: MPSImageThresholdBinary =
    {
        [unowned self] in
        
        return MPSImageThresholdBinary(device: self.device!, thresholdValue: 0.5, maximumValue: 1, linearGrayColorTransform: nil)
    }()
    
    // MARK: Initialisation
    
    override init(frame frameRect: CGRect, device: MTLDevice?)
    {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        
        framebufferOnly = false
        colorPixelFormat = MTLPixelFormat.BGRA8Unorm
        
        layer.borderColor = UIColor.whiteColor().CGColor
        layer.borderWidth = 1
   
        drawableSize = CGSize(width: 1024, height: 1024)
        
        setUpMetal()
    }

    required init(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setUpMetal()
    {
        posix_memalign(&particlesMemory, alignment, particlesMemoryByteSize)
        
        particlesVoidPtr = COpaquePointer(particlesMemory)
        particlesParticlePtr = UnsafeMutablePointer<Int>(particlesVoidPtr)
        particlesParticleBufferPtr = UnsafeMutableBufferPointer(start: particlesParticlePtr, count: particleCount)
        
        for index in particlesParticleBufferPtr.startIndex ..< particlesParticleBufferPtr.endIndex
        {
            particlesParticleBufferPtr[index] = Int(arc4random_uniform(1024))
        }
        
        let threadExecutionWidth = paintingShaderPipelineState.threadExecutionWidth
        
        threadsPerThreadgroup = MTLSize(width:threadExecutionWidth,height:1,depth:1)
        threadgroupsPerGrid = MTLSize(width:particleCount / threadExecutionWidth, height:1, depth:1)
        
        particlesBufferNoCopy = device!.newBufferWithBytesNoCopy(particlesMemory,
            length: Int(particlesMemoryByteSize),
            options: MTLResourceOptions.StorageModeShared,
            deallocator: nil)
    }
    
    // MARK: Touch handlers
    
    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?)
    {
        guard let touch = touches.first else
        {
            return
        }
        
        touchLocation = touch.locationInView(self)
    }
    
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?)
    {
        touchLocation.x = -1
        touchLocation.y = -1
    }
    
    // MARK: MetalKit view loop
    
    override func drawRect(dirtyRect: CGRect)
    {        
        let commandBuffer = commandQueue.commandBuffer()
        let commandEncoder = commandBuffer.computeCommandEncoder()
        
        commandEncoder.setComputePipelineState(paintingShaderPipelineState)
        
        commandEncoder.setBuffer(particlesBufferNoCopy, offset: 0, atIndex: 0)
        
        var xLocation = Int(touchLocation.x)
        let xLocationBuffer = device!.newBufferWithBytes(&xLocation, length: sizeof(Int), options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        var yLocation = Int(touchLocation.y)
        let yLocationBuffer = device!.newBufferWithBytes(&yLocation, length: sizeof(Int), options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        commandEncoder.setBuffer(xLocationBuffer, offset: 0, atIndex: 1)
        commandEncoder.setBuffer(yLocationBuffer, offset: 0, atIndex: 2)
  
        commandEncoder.setTexture(paintingTexture, atIndex: 0)
        
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder.endEncoding()
        
        guard let drawable = currentDrawable else
        {
            Swift.print("currentDrawable returned nil")
            
            return
        }
        
        blur.encodeToCommandBuffer(commandBuffer,
            sourceTexture: paintingTexture,
            destinationTexture: intermediateTexture)
        
        threshold.encodeToCommandBuffer(commandBuffer,
            sourceTexture: intermediateTexture,
            destinationTexture: drawable.texture)

        commandBuffer.commit()
        
        drawable.present()
        
        for index in particlesParticleBufferPtr.startIndex ..< particlesParticleBufferPtr.endIndex
        {
            particlesParticleBufferPtr[index] = Int(arc4random_uniform(1024))
        }
    }
}

