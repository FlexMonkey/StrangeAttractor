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
    var pointCount = 4_194_304
    let alignment:Int = 0x4000
    let pointMemoryByteSize:Int

    var pointMemory:UnsafeMutablePointer<Void> = nil
    let pointVoidPtr: COpaquePointer
    let pointPtr: UnsafeMutablePointer<float3>
    let pointBufferPtr: UnsafeMutableBufferPointer<float3>

    let region: MTLRegion
    let bytesPerRow: UInt
    let blankBitmapRawData : [UInt8]
    
    var angle: Float = 0
    var pointIndex: UInt = 1
    private var frameStartTime: CFAbsoluteTime!
    private var frameNumber = 0
    
    private var width: CGFloat
    let centerBuffer: MTLBuffer
    
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

        func rnd() -> Float
        {
            return -5 + 10 * (Float(arc4random_uniform(1000)) / 1000)
        }

        pointBufferPtr[pointBufferPtr.startIndex] = float3(rnd(), rnd(), rnd())
        
        frameStartTime = CFAbsoluteTimeGetCurrent()
    }
    
    required init(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func drawRect(rect: CGRect)
    {
        frameNumber += 1
        
        if frameNumber == 100
        {
            let frametime = (CFAbsoluteTimeGetCurrent() - frameStartTime) / 100
            print(String(format: " at %.1f fps", 1 / frametime))
            frameStartTime = CFAbsoluteTimeGetCurrent()
            frameNumber = 0
        }
        
        let commandBuffer = commandQueue.commandBuffer()
        let commandEncoder = commandBuffer.computeCommandEncoder()
        
        commandEncoder.setComputePipelineState(pipelineState)
        
        let pointBuffer = device!.newBufferWithBytesNoCopy(
            pointMemory,
            length: Int(pointMemoryByteSize),
            options: .CPUCacheModeDefaultCache,
            deallocator: nil)
        
        commandEncoder.setBuffer(pointBuffer, offset: 0, atIndex: 0)
        commandEncoder.setBuffer(pointBuffer, offset: 0, atIndex: 1)
        
        let angleBuffer = device!.newBufferWithBytes(
            &angle,
            length: sizeof(Float),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        commandEncoder.setBuffer(angleBuffer, offset: 0, atIndex: 2)
        
        let pointIndexBuffer = device!.newBufferWithBytes(
            &pointIndex,
            length: sizeof(UInt),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        commandEncoder.setBuffer(pointIndexBuffer, offset: 0, atIndex: 3)
        
        commandEncoder.setBuffer(centerBuffer, offset: 0, atIndex: 4)
        
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
        
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        
        drawable.present()
        
        angle += 0.005
        pointIndex += 1
    }
    
    
    
}