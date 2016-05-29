//
//  StrangeAttractorRenderer.swift
//  StrangeAttractor
//
//  Created by Simon Gladman on 27/05/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import Foundation
import MetalKit
import simd.vector

class StrangeAttractorRenderer: MTKView
{
    private var pointCount =  262144 // 262144 points at 60fps / 20 iterations per frame = 3.64 mins
    private let alignment:Int = 0x4000
    private let pointMemoryByteSize:Int

    private var pointMemory:UnsafeMutablePointer<Void> = nil
    private let pointVoidPtr: COpaquePointer
    private let pointPtr: UnsafeMutablePointer<float3>
    private let pointBufferPtr: UnsafeMutableBufferPointer<float3>

    private let region: MTLRegion
    private let bytesPerRow: UInt
    private let blankBitmapRawData : [UInt8]
    
    private var angle: Float = 0
    private var pointIndex: UInt = 1
    private var frameStartTime: CFAbsoluteTime!
    private var frameNumber = 0
    
    private var width: CGFloat
    private let centerBuffer: MTLBuffer
    
    private var scale: Float = 20.0
    private var pinchScale: CGFloat = 0 // scale at pinch begin
    
    private var resetPointIndex = false // schedule pointIndex to reset to 1 on next frame
    private var attractorTypeIndex: UInt = 0
    
    /// Number of solver iterations per frame
    var iterations = 20
    
    let segmentedControl = UISegmentedControl(items: ["Lorenz", "Chen Lee", "Halvorsen", "Lü Chen", "Hadley", "Rössler", "Lorenze Mod 2"])
    
    lazy var commandQueue: MTLCommandQueue =
    {
        return self.device!.newCommandQueue()
    }()
    
    lazy var defaultLibrary: MTLLibrary =
    {
        return self.device!.newDefaultLibrary()!
    }()
    
    lazy var pipelineState: MTLComputePipelineState =
    {
        guard let kernelFunction = self.defaultLibrary.newFunctionWithName("strangeAttractorKernel") else
        {
            fatalError("Unable to create kernel function for strangeAttractorKernel")
        }
        
        do
        {
            let pipelineState = try self.device!.newComputePipelineStateWithFunction(kernelFunction)
            return pipelineState
        }
        catch
        {
            fatalError("Unable to create pipeline state for strangeAttractorKernel")
        }
    }()
    
    lazy var rendererPipelineState: MTLComputePipelineState =
    {
        guard let kernelFunction = self.defaultLibrary.newFunctionWithName("strangeAttractorRendererKernel") else
        {
            fatalError("Unable to create kernel function for strangeAttractorKernel")
        }
        
        do
        {
            let pipelineState = try self.device!.newComputePipelineStateWithFunction(kernelFunction)
            return pipelineState
        }
        catch
        {
            fatalError("Unable to create pipeline state for strangeAttractorKernel")
        }
    }()
    
    lazy var threadsPerThreadgroup: MTLSize =
    {
        let threadExecutionWidth = self.pipelineState.threadExecutionWidth
        
        return MTLSize(width:threadExecutionWidth,height:1,depth:1)
    }()
    
    lazy var threadgroupsPerGrid: MTLSize =
    {
        [unowned self] in
        
        let threadExecutionWidth = self.pipelineState.threadExecutionWidth
        
        return MTLSize(width: self.pointCount / threadExecutionWidth, height:1, depth:1)
    }()
    
    required init(frame frameRect: CGRect, device: MTLDevice, width: CGFloat, contentScaleFactor: CGFloat)
    {
        self.width = width
 
        let pixelWidth = width * contentScaleFactor
        
        bytesPerRow = 4 * UInt(pixelWidth)
        region = MTLRegionMake2D(0, 0, Int(pixelWidth), Int(pixelWidth))
        blankBitmapRawData = [UInt8](count: Int(pixelWidth * pixelWidth * 4), repeatedValue: 0)
        
        pointMemoryByteSize = pointCount * sizeof(float3)
        
        posix_memalign(
            &pointMemory,
            alignment,
            pointMemoryByteSize)
        
        pointVoidPtr = COpaquePointer(pointMemory)
        pointPtr = UnsafeMutablePointer<float3>(pointVoidPtr)
        pointBufferPtr = UnsafeMutableBufferPointer(
            start: pointPtr,
            count: pointCount)
        
        var center = UInt(pixelWidth / 2)
        centerBuffer = device.newBufferWithBytes(
            &center,
            length: sizeof(UInt),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        super.init(
            frame: frameRect,
            device: device)
        
        self.contentScaleFactor = contentScaleFactor
        
        paused = true
        framebufferOnly = false

        pointBufferPtr[pointBufferPtr.startIndex] = float3(rnd(), rnd(), rnd())
        
        frameStartTime = CFAbsoluteTimeGetCurrent()
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchHandler))
        addGestureRecognizer(pinch)
        
        addSubview(segmentedControl)
        segmentedControl.addTarget(
            self,
            action: #selector(segmentedControlChangeHandler),
            forControlEvents: .ValueChanged)
        segmentedControl.selectedSegmentIndex = Int(attractorTypeIndex)
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        segmentedControl.frame = CGRect(
            origin: CGPointZero,
            size: CGSize(width: frame.width, height: segmentedControl.intrinsicContentSize().height))
    }
    
    required init(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    func segmentedControlChangeHandler()
    {
        resetPointIndex = true
    }

    func pinchHandler(recogniser: UIPinchGestureRecognizer)
    {
        switch recogniser.state
        {
        case .Began:
            pinchScale = CGFloat(scale)
        case .Changed:
            scale = min(max(Float(pinchScale * recogniser.scale), 10.0), 400)
        default:
            pinchScale = 0
        }
    }
    
    override func drawRect(rect: CGRect)
    {
        frameNumber += 1
        
        if frameNumber == 100
        {
            let frametime = (CFAbsoluteTimeGetCurrent() - frameStartTime) / 100
            print(String(format: "%.1f fps", 1 / frametime), "| pointIndex: \(pointIndex)")
            frameStartTime = CFAbsoluteTimeGetCurrent()
            frameNumber = 0
        }
        
        if resetPointIndex
        {
            pointBufferPtr[pointBufferPtr.startIndex] = float3(rnd(), rnd(), rnd())
            pointIndex = 1
            attractorTypeIndex = UInt(segmentedControl.selectedSegmentIndex)
            resetPointIndex = false
        }
        
        let commandBuffer = commandQueue.commandBuffer()
        
        let angleBuffer = device!.newBufferWithBytes(
            &angle,
            length: sizeof(Float),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)

        let scaleBuffer = device!.newBufferWithBytes(
            &scale,
            length: sizeof(Float),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        let attractorTypeIndexBuffer = device!.newBufferWithBytes(
            &attractorTypeIndex,
            length: sizeof(UInt),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        let pointBuffer = device!.newBufferWithBytesNoCopy(
            pointMemory,
            length: Int(pointMemoryByteSize),
            options: .CPUCacheModeDefaultCache,
            deallocator: nil)
        
        // calculate....
        
        for _ in 0 ... iterations
        {
            let commandEncoder = commandBuffer.computeCommandEncoder()
            
            commandEncoder.setComputePipelineState(pipelineState)
            
            let pointIndexBuffer = device!.newBufferWithBytes(
                &pointIndex,
                length: sizeof(UInt),
                options: MTLResourceOptions.CPUCacheModeDefaultCache)
            
            commandEncoder.setBuffer(pointBuffer, offset: 0, atIndex: 0)
            commandEncoder.setBuffer(pointBuffer, offset: 0, atIndex: 1)
            commandEncoder.setBuffer(pointIndexBuffer, offset: 0, atIndex: 3)
            commandEncoder.setBuffer(attractorTypeIndexBuffer, offset: 0, atIndex: 6)
            
            commandEncoder.dispatchThreadgroups(
                threadgroupsPerGrid,
                threadsPerThreadgroup: threadsPerThreadgroup)
            
            commandEncoder.endEncoding()
  
            pointIndex += 1
        }
        
        // render....
        
        let commandEncoder = commandBuffer.computeCommandEncoder()
        
        commandEncoder.setComputePipelineState(rendererPipelineState)

        let pointIndexBuffer = device!.newBufferWithBytes(
            &pointIndex,
            length: sizeof(UInt),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        commandEncoder.setBuffer(pointBuffer, offset: 0, atIndex: 0)
        commandEncoder.setBuffer(angleBuffer, offset: 0, atIndex: 2)
        commandEncoder.setBuffer(pointIndexBuffer, offset: 0, atIndex: 3)
        commandEncoder.setBuffer(centerBuffer, offset: 0, atIndex: 4)
        commandEncoder.setBuffer(scaleBuffer, offset: 0, atIndex: 5)
        
        guard let drawable = currentDrawable else
        {
            commandEncoder.endEncoding()
            
            print("metalLayer.nextDrawable() returned nil")
            
            return
        }
        
        drawable.texture.replaceRegion(
            self.region,
            mipmapLevel: 0,
            withBytes: blankBitmapRawData,
            bytesPerRow: Int(bytesPerRow))
        
        commandEncoder.setTexture(drawable.texture, atIndex: 0)
        
        commandEncoder.dispatchThreadgroups(
            threadgroupsPerGrid,
            threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder.endEncoding()
        
        // finish....
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        currentDrawable?.present()
        
        angle += 0.005
    }
    
    func rnd() -> Float
    {
        return 1 + Float(drand48())
    }
    
}