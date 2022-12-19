import simd
import MetalKit
import Swift

class Renderer: NSObject, MTKViewDelegate {
    
    var parent: ContentView
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var drawPipeline: MTLComputePipelineState!
    var updatePipeline: MTLComputePipelineState!
    var agents = [Agent]()
    
    init(_ parent: ContentView) {
        self.parent = parent
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        }
        self.metalCommandQueue = metalDevice.makeCommandQueue()
        
        // metal funktionen laden
        do {
            guard let library = metalDevice.makeDefaultLibrary() else {
                fatalError()
            }
            guard let kernel = library.makeFunction(name: "updateTexture") else {
                fatalError()
            }
            drawPipeline = try metalDevice.makeComputePipelineState(function: kernel)
            
            guard let update = library.makeFunction(name: "updateAgent") else {
                fatalError()
            }
            updatePipeline = try metalDevice.makeComputePipelineState(function: update)
            
        } catch {
            fatalError()
        }
        
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        
        agents = generateAgents(width: width, height: height, shape: Shape.noShape)
    }
    
    // function to generate agents
    func generateAgents(width : Int, height: Int, shape: Shape) -> [Agent]{
        
        let centre = SIMD2<Float32>(Float(width) / 2.0, Float(height) / 2.0)
        var startPos = SIMD2<Float32>(0, 0)
        var angle : Float = 0.0
        var agents = [Agent]();
        
        for _ in 1...NUMAGENTS {
            angle = Float.random(in: 0.0 ..< 1.0) * Float.pi * 2
            
            switch(shape)
            {
            case Shape.circle:
                startPos = centre + randv_circle(min_radius: 0,max_radius: Float(height) * 0.3)
                break;
            case Shape.ring:
                startPos = centre + randv_circle(min_radius: Float(height) * 0.1,max_radius: Float(height) * 0.3)
                break
            default: // also no Shape
                startPos = vector_float2(Float.random(in: 0.0...Float(width)), Float.random(in: 0.0...Float(height)))
            }
            
            agents.append(Agent(position: startPos, angle: angle))
        }
        
        return agents
    }
    
    func draw(in view: MTKView) {
        // get the 2D texture
        guard let drawable = view.currentDrawable else {
            return
        }
        
        // create a buffer to execute
        // and an encoder to encode data into the buffer
        let commandBuffer = metalCommandQueue.makeCommandBuffer()!
        let  encoder = commandBuffer.makeComputeCommandEncoder()!
        
        // tell encoder to do updateTexture with drawPipeline
        encoder.setComputePipelineState(drawPipeline)
        updateTexture(renderEncoder: encoder, drawable: drawable)
        
        // tell encoder to update agents with updatePipeline
        // difference is thread count and layout
        encoder.setComputePipelineState(updatePipeline)
        let res = updateAgents(encoder: encoder, drawable: drawable)
        
        // stop the setup and commit
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // wait until all agents were updated
        commandBuffer.waitUntilCompleted()
        
        // get the rusult of compute shader and save them
        let agentBufferPtr = res.contents().bindMemory(to: Agent.self, capacity: MemoryLayout<Agent>.size * agents.count)

        agents = Array(UnsafeBufferPointer(start: agentBufferPtr, count: agents.count))
    }
    
    // configure GPU execution pipeline to draw on screen #Pixel threads
    func updateTexture(renderEncoder : MTLComputeCommandEncoder, drawable : CAMetalDrawable) {
        renderEncoder.setTexture(drawable.texture, index: 0)
        
        let agentBuffer = makeAgentBuffer()
        renderEncoder.setBuffer(agentBuffer, offset: 0, index: 0)
        
        let workGroupWidth = drawPipeline.threadExecutionWidth
        let workGroupHeight = updatePipeline.maxTotalThreadsPerThreadgroup / workGroupWidth
        let threadsPerGroup = MTLSizeMake(workGroupWidth, workGroupHeight, 1)
        let threadsPerGrid = MTLSizeMake(Int(drawable.texture.width), Int(drawable.texture.height), 1)
        
        renderEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
    }
    
    // configure GPU execution pipeline to update the Agents #Agents threads
    func updateAgents(encoder : MTLComputeCommandEncoder, drawable : CAMetalDrawable) -> MTLBuffer
    {
        // param #0 : Agents
        let agentBuffer = makeAgentBuffer()
        encoder.setBuffer(agentBuffer, offset: 0, index: 0)
        
        let resBuffer = metalDevice.makeBuffer(length: MemoryLayout<Agent>.size * agents.count, options: .storageModeShared)
        encoder.setBuffer(resBuffer, offset: 0,index: 1)
        
        // Calculate the maximum threads per threadgroup based on the thread execution width.
        let w = updatePipeline.threadExecutionWidth
        let h = updatePipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        
        
        let threadsPerGrid = MTLSize(width: agents.count,
                                     height: 1,
                                     depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        return resBuffer!
    }
    
    // create a shared buffer for the Agents between the CPU and GPU
    func makeAgentBuffer() -> MTLBuffer? {
        var memory: UnsafeMutableRawPointer? = nil
        let agentCount: Int = agents.count
        let memory_size = agentCount * MemoryLayout<Agent>.stride
        let page_size = 0x1000
        let allocation_size = (memory_size + page_size - 1) & (~(page_size - 1))
        
        posix_memalign(&memory, page_size, allocation_size)
        memcpy(memory, &agents, allocation_size)
        
        /*
         shared: CPU and GPU,
         private: GPU only
         managed: both CPU and GPU have copies, changes must be explicitly signalled/sychronized
         memoryless: contents exist only temporarily for renderpass
         */
        
        let buffer = metalDevice.makeBuffer(
            bytes: memory!, length: allocation_size, options: .storageModeShared
        )
        
        free(memory)
        
        return buffer
        
    }
}

// generates random points on circle
func randv_circle(min_radius : Float, max_radius : Float) ->SIMD2<Float>{
    let r2_max = max_radius * max_radius
    let r2_min = min_radius * min_radius
    let r = sqrt(Float.random(in: 0...1 ) * (r2_max - r2_min) + r2_min)
    let t = Float.random(in: 0...1) * Float.pi * 2
    return rotateRadians(v: SIMD2<Float>(r, 0),radians: t)
}



// rotates a vector
func rotateRadians(v:SIMD2<Float>, radians:Float) -> SIMD2<Float>
{
    let ca = cos(radians);
    let sa = sin(radians);
    return SIMD2<Float>(ca*v[0] - sa*v[1], sa*v[0] + ca*v[1]);
}

enum Shape
{
    case noShape, circle, ring
}
