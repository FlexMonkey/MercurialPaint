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

let particleCount: Int = 2048

class MercurialPaint: UIView
{
    // MARK: Constants
    
    let device = MTLCreateSystemDefaultDevice()!
    let alignment:Int = 0x4000
    let particlesMemoryByteSize:Int = particleCount * sizeof(Int)
    let halfPi = CGFloat(M_PI_2)
    
    let ciContext = CIContext(EAGLContext: EAGLContext(API: EAGLRenderingAPI.OpenGLES2), options: [kCIContextWorkingColorSpace: NSNull()])
    let heightMapFilter = CIFilter(name: "CIHeightFieldFromMask")!
    let shadedMaterialFilter = CIFilter(name: "CIShadedMaterial")!
    let maskToAlpha = CIFilter(name: "CIMaskToAlpha")!
    
    // MARK: Private variables
    
    private var threadsPerThreadgroup:MTLSize!
    private var threadgroupsPerGrid:MTLSize!
    
    private var particlesMemory:UnsafeMutablePointer<Void> = nil
    private var particlesVoidPtr: COpaquePointer!
    private var particlesParticlePtr: UnsafeMutablePointer<Int>!
    private var particlesParticleBufferPtr: UnsafeMutableBufferPointer<Int>!
    
    private var particlesBufferNoCopy: MTLBuffer!
    private var touchLocations = [CGPoint]()
    private var touchForce:Float = 0
    
    private var pendingUpdate = false
    private var isBusy = false
    
    private var isDrawing = false
    {
        didSet
        {
            imageView.hidden = isDrawing
            metalView.hidden = !isDrawing
        }
    }
    
    // MARK: Public
    
    var shadingImage: UIImage?
    {
        didSet
        {
            applyCoreImageFilter()
        }
    }
    
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
            particlesParticleBufferPtr[index] = Int(arc4random_uniform(9999))
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
        
        touchForce = touch.type == .Stylus
            ? Float(touch.force / touch.maximumPossibleForce)
            : 0.5
        
        isDrawing = true
        
        touchLocations = [touch.locationInView(self)]
    }
    
    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?)
    {
        guard let touch = touches.first, coalescedTouches =  event?.coalescedTouchesForTouch(touch) else
        {
            return
        }

        touchForce = touch.type == .Stylus
            ? Float(touch.force / touch.maximumPossibleForce)
            : 0.5
        
        touchLocations = coalescedTouches.map{ return $0.locationInView(self) }
    }
    
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?)
    {
        isDrawing = false
        
        touchLocations = [CGPoint](count: 4, repeatedValue: CGPoint(x: -1, y: 01))
        
        applyCoreImageFilter()
    }
    
    // MARK: Core Image Stuff
    
    func applyCoreImageFilter()
    {
        guard let drawable = metalView.currentDrawable else
        {
            print("currentDrawable returned nil")
            
            return
        }
        
        guard !isBusy else
        {
            pendingUpdate = true
            return
        }
        
        guard let shadingImage = shadingImage, ciShadingImage = CIImage(image: shadingImage) else
        {
            return
        }
        
        isBusy = true
        
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
                self.isBusy = false
                
                if self.pendingUpdate
                {
                    self.pendingUpdate = false
                    
                    self.applyCoreImageFilter()
                }
            }
        }
    }
    
    func touchLocationsToVector(xy: XY) -> vector_int4
    {
        func getValue(point: CGPoint, xy: XY) -> Int32
        {
            switch xy
            {
            case .X:
                return Int32(point.x * 2)
            case .Y:
                return Int32(point.y * 2)
            }
        }
        
        let a = touchLocations.count > 0 ? getValue(touchLocations[0], xy: xy) : -1
        let b = touchLocations.count > 1 ? getValue(touchLocations[1], xy: xy) : -1
        let c = touchLocations.count > 2 ? getValue(touchLocations[2], xy: xy) : -1
        let d = touchLocations.count > 3 ? getValue(touchLocations[3], xy: xy) : -1
        
        let returnValue = vector_int4(a, b, c, d)
        
        return returnValue
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
    
        var xLocation = touchLocationsToVector(.X)
        let xLocationBuffer = device.newBufferWithBytes(&xLocation,
            length: sizeof(vector_int4),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        var yLocation = touchLocationsToVector(.Y)
        let yLocationBuffer = device.newBufferWithBytes(&yLocation,
            length: sizeof(vector_int4),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        let touchForceBuffer = device.newBufferWithBytes(&touchForce,
            length: sizeof(Float),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        commandEncoder.setBuffer(xLocationBuffer, offset: 0, atIndex: 1)
        commandEncoder.setBuffer(yLocationBuffer, offset: 0, atIndex: 2)
        commandEncoder.setBuffer(touchForceBuffer, offset: 0, atIndex: 3)
        
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

enum XY
{
    case X, Y
}

