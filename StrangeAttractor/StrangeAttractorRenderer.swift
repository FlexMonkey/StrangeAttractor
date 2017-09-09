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
    fileprivate var pointCount =  262144 // 262144 points at 60fps / 20 iterations per frame = 3.64 mins
    fileprivate let alignment:Int = 0x4000
    fileprivate let pointMemoryByteSize:Int

    fileprivate var pointMemory:UnsafeMutableRawPointer? = nil
    fileprivate let pointVoidPtr: OpaquePointer
    fileprivate let pointPtr: UnsafeMutablePointer<float3>
    fileprivate let pointBufferPtr: UnsafeMutableBufferPointer<float3>

    fileprivate let region: MTLRegion
    fileprivate let bytesPerRow: UInt
    fileprivate let blankBitmapRawData : [UInt8]
    
    fileprivate var angle: Float = 0
    fileprivate var pointIndex: UInt = 1
    fileprivate var frameStartTime: CFAbsoluteTime!
    fileprivate var frameNumber = 0
    
    fileprivate var panStartAngle: Float = 0
    fileprivate var panning: Bool = false
    
    fileprivate var width: CGFloat
    fileprivate let centerBuffer: MTLBuffer
    
    fileprivate var scale: Float = 20.0
    fileprivate var pinchScale: CGFloat = 0 // scale at pinch begin
    
    fileprivate var resetPointIndex = false // schedule pointIndex to reset to 1 on next frame
    fileprivate var attractorTypeIndex: UInt = 0
    
    /// Number of solver iterations per frame
    var iterations = 20
    
    let segmentedControl = UISegmentedControl(items: ["Lorenz", "Chen Lee", "Halvorsen", "Lü Chen", "Hadley", "Rössler", "Lorenze Mod 2"])
    
    lazy var commandQueue: MTLCommandQueue =
    {
        return self.device!.makeCommandQueue()!
    }()
    
    lazy var defaultLibrary: MTLLibrary =
    {
        return self.device!.makeDefaultLibrary()!
    }()
    
    lazy var pipelineState: MTLComputePipelineState =
    {
        guard let kernelFunction = self.defaultLibrary.makeFunction(name: "strangeAttractorKernel") else
        {
            fatalError("Unable to create kernel function for strangeAttractorKernel")
        }
        
        do
        {
            let pipelineState = try self.device!.makeComputePipelineState(function: kernelFunction)
            return pipelineState
        }
        catch
        {
            fatalError("Unable to create pipeline state for strangeAttractorKernel")
        }
    }()
    
    lazy var rendererPipelineState: MTLComputePipelineState =
    {
        guard let kernelFunction = self.defaultLibrary.makeFunction(name: "strangeAttractorRendererKernel") else
        {
            fatalError("Unable to create kernel function for strangeAttractorKernel")
        }
        
        do
        {
            let pipelineState = try self.device!.makeComputePipelineState(function: kernelFunction)
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
        blankBitmapRawData = [UInt8](repeating: 0, count: Int(pixelWidth * pixelWidth * 4))
        
        pointMemoryByteSize = pointCount * MemoryLayout<float3>.size
        
        posix_memalign(
            &pointMemory,
            alignment,
            pointMemoryByteSize)
        
        pointVoidPtr = OpaquePointer(pointMemory!)
        pointPtr = UnsafeMutablePointer<float3>(pointVoidPtr)
        pointBufferPtr = UnsafeMutableBufferPointer(
            start: pointPtr,
            count: pointCount)
        
        var center = UInt(pixelWidth / 2)
        centerBuffer = device.makeBuffer(
            bytes: &center,
            length: MemoryLayout<UInt>.size,
            options: MTLResourceOptions())!
        
        super.init(
            frame: frameRect,
            device: device)
        
        self.contentScaleFactor = contentScaleFactor
        
        isPaused = true
        framebufferOnly = false

        pointBufferPtr[pointBufferPtr.startIndex] = float3(rnd(), rnd(), rnd())
        
        frameStartTime = CFAbsoluteTimeGetCurrent()
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(StrangeAttractorRenderer.pinchHandler(_:)))
        addGestureRecognizer(pinch)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(StrangeAttractorRenderer.panHandler(_:)))
        addGestureRecognizer(pan)
        
        addSubview(segmentedControl)
        segmentedControl.addTarget(
            self,
            action: #selector(StrangeAttractorRenderer.segmentedControlChangeHandler),
            for: .valueChanged)
        segmentedControl.selectedSegmentIndex = Int(attractorTypeIndex)
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        segmentedControl.frame = CGRect(
            origin: CGPoint.zero,
            size: CGSize(width: frame.width, height: segmentedControl.intrinsicContentSize.height))
    }
    
    required init(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func segmentedControlChangeHandler()
    {
        resetPointIndex = true
    }

    @objc func panHandler(_ recogniser: UIPanGestureRecognizer)
    {
        switch recogniser.state
        {
        case .began:
            panning = true
            panStartAngle = angle
        case .changed:
            angle = panStartAngle + Float(CGFloat(M_PI) * recogniser.translation(in: self).x / width)
        default:
            panning = false
        }
    }
    
    @objc func pinchHandler(_ recogniser: UIPinchGestureRecognizer)
    {
        switch recogniser.state
        {
        case .began:
            pinchScale = CGFloat(scale)
        case .changed:
            scale = min(max(Float(pinchScale * recogniser.scale), 10.0), 400)
        default:
            pinchScale = 0
        }
    }
    
    override func draw(_ rect: CGRect)
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
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        
        let angleBuffer = device!.makeBuffer(
            bytes: &angle,
            length: MemoryLayout<Float>.size,
            options: MTLResourceOptions())

        let scaleBuffer = device!.makeBuffer(
            bytes: &scale,
            length: MemoryLayout<Float>.size,
            options: MTLResourceOptions())
        
        let attractorTypeIndexBuffer = device!.makeBuffer(
            bytes: &attractorTypeIndex,
            length: MemoryLayout<UInt>.size,
            options: MTLResourceOptions())
        
        let pointBuffer = device!.makeBuffer(
            bytesNoCopy: pointMemory!,
            length: Int(pointMemoryByteSize),
            options: MTLResourceOptions(),
            deallocator: nil)
        
        // calculate....
        
        for _ in 0 ... iterations
        {
            let commandEncoder = commandBuffer?.makeComputeCommandEncoder()
            
            commandEncoder?.setComputePipelineState(pipelineState)
            
            let pointIndexBuffer = device!.makeBuffer(
                bytes: &pointIndex,
                length: MemoryLayout<UInt>.size,
                options: MTLResourceOptions())
            
            commandEncoder?.setBuffer(pointBuffer, offset: 0, index: 0)
            commandEncoder?.setBuffer(pointBuffer, offset: 0, index: 1)
            commandEncoder?.setBuffer(pointIndexBuffer, offset: 0, index: 3)
            commandEncoder?.setBuffer(attractorTypeIndexBuffer, offset: 0, index: 6)
            
            commandEncoder?.dispatchThreadgroups(
                threadgroupsPerGrid,
                threadsPerThreadgroup: threadsPerThreadgroup)
            
            commandEncoder?.endEncoding()
  
            pointIndex += 1
        }
        
        // render....
        
        let commandEncoder = commandBuffer?.makeComputeCommandEncoder()
        
        commandEncoder?.setComputePipelineState(rendererPipelineState)

        let pointIndexBuffer = device!.makeBuffer(
            bytes: &pointIndex,
            length: MemoryLayout<UInt>.size,
            options: MTLResourceOptions())
        
        commandEncoder?.setBuffer(pointBuffer, offset: 0, index: 0)
        commandEncoder?.setBuffer(angleBuffer, offset: 0, index: 2)
        commandEncoder?.setBuffer(pointIndexBuffer, offset: 0, index: 3)
        commandEncoder?.setBuffer(centerBuffer, offset: 0, index: 4)
        commandEncoder?.setBuffer(scaleBuffer, offset: 0, index: 5)
        
        guard let drawable = currentDrawable else
        {
            commandEncoder?.endEncoding()
            
            print("metalLayer.nextDrawable() returned nil")
            
            return
        }
        
        drawable.texture.replace(
            region: self.region,
            mipmapLevel: 0,
            withBytes: blankBitmapRawData,
            bytesPerRow: Int(bytesPerRow))
        
        commandEncoder?.setTexture(drawable.texture, index: 0)
        
        commandEncoder?.dispatchThreadgroups(
            threadgroupsPerGrid,
            threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder?.endEncoding()
        
        // finish....
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        
        currentDrawable?.present()
        
        if !panning {
            angle += 0.005
        }
    }
    
    func rnd() -> Float
    {
        return 1 + Float(drand48())
    }
    
}
