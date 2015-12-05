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

class MercurialPaint: UIView
{
    // MARK: Constants
    
    let device = MTLCreateSystemDefaultDevice()!
    let particleCount: Int = 1024
    let alignment:Int = 0x4000
    let particlesMemoryByteSize:Int = 1024 * sizeof(Int)
    
    let ciContext = CIContext(EAGLContext: EAGLContext(API: EAGLRenderingAPI.OpenGLES2), options: [kCIContextWorkingColorSpace: NSNull()])
    let heightMapFilter = CIFilter(name: "CIHeightFieldFromMask")!
    let shadedMaterialFilter = CIFilter(name: "CIShadedMaterial")!
    let maskToAlpha = CIFilter(name: "CIMaskToAlpha")!
    
    // MARK: Priavte variables
    
    private var threadsPerThreadgroup:MTLSize!
    private var threadgroupsPerGrid:MTLSize!
    
    private var particlesMemory:UnsafeMutablePointer<Void> = nil
    private var particlesVoidPtr: COpaquePointer!
    private var particlesParticlePtr: UnsafeMutablePointer<Int>!
    private var particlesParticleBufferPtr: UnsafeMutableBufferPointer<Int>!
    
    private var particlesBufferNoCopy: MTLBuffer!
    
    private var touchLocation = CGPoint(x: -1, y: -1)
    
    // MARK: Public
    
    var shadingImage: UIImage?
    
    // MARK: UI components
    
    var metalView: MTKView!
    let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024))
 
    // MARK: Lazy variables
    
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(MTLPixelFormat.RGBA8Unorm,
        width: 2048,
        height: 2048,
        mipmapped: false)
    
    lazy var paintingTexture: MTLTexture =
    {
        [unowned self] in

        return self.device.newTextureWithDescriptor(self.textureDescriptor)
    }()
    
    lazy var intermediateTexture: MTLTexture =
    {
        [unowned self] in
        
        return self.device.newTextureWithDescriptor(self.textureDescriptor)
        }()
    
    lazy var paintingShaderPipelineState: MTLComputePipelineState =
    {
       [unowned self] in
        
        do
        {
            let library = self.device.newDefaultLibrary()!
            
            let kernelFunction = library.newFunctionWithName("mercurialPaintShader")
            let pipelineState = try self.device.newComputePipelineStateWithFunction(kernelFunction!)
            
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
        
        return self.device.newCommandQueue()
    }()
    
    lazy var blur: MPSImageGaussianBlur =
    {
        [unowned self] in
        
        return MPSImageGaussianBlur(device: self.device, sigma: 3)
        }()
    
    lazy var threshold: MPSImageThresholdBinary =
    {
        [unowned self] in
        
        return MPSImageThresholdBinary(device: self.device, thresholdValue: 0.5, maximumValue: 1, linearGrayColorTransform: nil)
    }()
    
    
    
    // MARK: Initialisation
    
    override init(frame frameRect: CGRect)
    {
        super.init(frame: frameRect)
        
        metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024), device: device)
        
        metalView.framebufferOnly = false
        metalView.colorPixelFormat = MTLPixelFormat.BGRA8Unorm
        
        metalView.delegate = self
        
        layer.borderColor = UIColor.whiteColor().CGColor
        layer.borderWidth = 1
   
        metalView.drawableSize = CGSize(width: 2048, height: 2048)
        
        imageView.hidden = true
        
        addSubview(metalView)
        addSubview(imageView)
        
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
        
        particlesBufferNoCopy = device.newBufferWithBytesNoCopy(particlesMemory,
            length: Int(particlesMemoryByteSize),
            options: MTLResourceOptions.StorageModeShared,
            deallocator: nil)
    }
    
    // MARK: Touch handlers
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?)
    {
        guard let touch = touches.first else
        {
            return
        }
        
        imageView.hidden = true
        metalView.hidden = false
        
        touchLocation = touch.locationInView(self)
    }
    
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
        imageView.hidden = false
        metalView.hidden = true
        
        touchLocation.x = -1
        touchLocation.y = -1
        
        applyCoreImageFilter()
    }
    
    // MARK: Core Image Stuff
    
    func applyCoreImageFilter()
    {
        print("core image!!!")
        
        guard let drawable = metalView.currentDrawable else
        {
            print("currentDrawable returned nil")
            
            return
        }
        
        guard let shadingImage = shadingImage, ciShadingImage = CIImage(image: shadingImage) else
        {
            return
        }
        
        let mercurialImage = CIImage(MTLTexture: drawable.texture, options: nil)
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            let heightMapFilter = self.heightMapFilter.copy()
            let shadedMaterialFilter = self.shadedMaterialFilter.copy()
            let maskToAlpha = self.maskToAlpha.copy()
            
            maskToAlpha.setValue(mercurialImage,
                forKey: kCIInputImageKey)
            
            heightMapFilter.setValue(maskToAlpha.valueForKey(kCIOutputImageKey),
                forKey: kCIInputImageKey)
            
            shadedMaterialFilter.setValue(heightMapFilter.valueForKey(kCIOutputImageKey),
                forKey: kCIInputImageKey)
            
            shadedMaterialFilter.setValue(ciShadingImage,
                forKey: "inputShadingImage")
            
            let filteredImageData = shadedMaterialFilter.valueForKey(kCIOutputImageKey) as! CIImage
            let filteredImageRef = self.ciContext.createCGImage(filteredImageData,
                fromRect: filteredImageData.extent)
            
            let finalImage = UIImage(CGImage: filteredImageRef)
            
            dispatch_async(dispatch_get_main_queue())
            {
                self.imageView.image = finalImage
            }
        }
    }
}

extension MercurialPaint: MTKViewDelegate
{
    func mtkView(view: MTKView, drawableSizeWillChange size: CGSize)
    {
        
    }
    
    func drawInMTKView(view: MTKView)
    {
        let commandBuffer = commandQueue.commandBuffer()
        let commandEncoder = commandBuffer.computeCommandEncoder()
        
        commandEncoder.setComputePipelineState(paintingShaderPipelineState)
        
        commandEncoder.setBuffer(particlesBufferNoCopy, offset: 0, atIndex: 0)
        
        var xLocation = Int(touchLocation.x * 2)
        let xLocationBuffer = device.newBufferWithBytes(&xLocation, length: sizeof(Int), options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        var yLocation = Int(touchLocation.y * 2)
        let yLocationBuffer = device.newBufferWithBytes(&yLocation, length: sizeof(Int), options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        commandEncoder.setBuffer(xLocationBuffer, offset: 0, atIndex: 1)
        commandEncoder.setBuffer(yLocationBuffer, offset: 0, atIndex: 2)
        
        commandEncoder.setTexture(paintingTexture, atIndex: 0)
        
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder.endEncoding()
        
        guard let drawable = metalView.currentDrawable else
        {
            print("currentDrawable returned nil")
            
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



