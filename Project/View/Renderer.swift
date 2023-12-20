import simd
import MetalKit
import Swift

// Ist verantwortlich fuer das Initialisieren der GPU
// bereitet Daten vor um diese auf die GPU zu laden
// veranlasst das
class Renderer: NSObject, MTKViewDelegate {
    
    // Eigenschaften, um sich bspw die Referenz auf die Grafikkarte zu merken
    var parent: ContentView
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var drawPipeline: MTLComputePipelineState!
    var updatePipeline: MTLComputePipelineState!
    // Liste von Agenten, welche in jedem Frame auf die Grafikkarte übertragen und bearbeitet weden
    var agents = [Agent]()
    
    init(_ parent: ContentView) {
        self.parent = parent
        // Apple spezifisch um Grafikkarte und Pipeline anzusprechen
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        }
        self.metalCommandQueue = metalDevice.makeCommandQueue()
        
        // Metal Funktionen aus Shader laden, um diese für die Pipeline zur Verfuegung stellen zu koennen
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
        
        // neue Agenten generieren, wenn oberfläche geladen wird
        agents = generateAgents(width: width, height: height, shape: Shape.circle,direction: Direction.outward)
    }
    
    // Generiert die Agenten, diese werden in einer ausgewaehlten "Shape" auf dem Bildschirm verteilt
    // und bekommen einen zufälligen Winkel in welchen Sie initial Zeigen
    func generateAgents(width : Int, height: Int, shape: Shape, direction: Direction) -> [Agent]{
        let centre = SIMD2<Float32>(Float(width) / 2.0, Float(height) / 2.0)
        var startPos = SIMD2<Float32>(0, 0)
        var angle : Float = 0.0
        var agents = [Agent]();
        
        // jeden einzelnen Agenten auf der Oberfläche verteilen
        for i in 1...NUMAGENTS {
 
            // Position festlegen
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
            
            // winkel festlegen
            switch direction{
            case Direction.inward:
                angle = atan2(centre.y-startPos.y,centre.x-startPos.x);
                break;
            case Direction.outward:
                angle = atan2(centre.y-startPos.y,centre.x-startPos.x) + Float.pi;
                break;
            case Direction.random:
                angle = Float.random(in: 0.0 ..< 1.0) * Float.pi * 2
                break
            }
            
            // Farbe festlegen
            var color : vector_float3 = vector_float3(1.0,1.0,1.0);
            
            // Haelfte der Agenten rot, anderer Haelfte gruen
            if(i  > NUMAGENTS/2) {
                color = vector_float3(1.0,0.0,0.0);
            }
            else {
                color = vector_float3(0.0,1.0,0.0);
            }
        
//
//            let vals : [vector_float3] = [vector_float3(1.0,0.0,0.0),vector_float3(0.0,1.0,0.0),vector_float3(0.0,0.0,1.0),vector_float3(0.5,0.2,0.1),vector_float3(0.0,0.6,0.4),vector_float3(0.0,0.1,0.9),];
//
            let vals : [vector_float3] = [vector_float3(1.0,0.0,0.0),vector_float3(0.0,1.0,0.0)];
            
            
            
            color = vals.randomElement()!
         
            // neuen Agenten im Speicher mit seinen Werten anlegen
            agents.append(Agent(position: startPos, angle: angle, color: color))
        }
        
        return agents
    }
    
    func draw(in view: MTKView) {
        // get the 2D texture
        guard let drawable = view.currentDrawable else {
            return
        }
        
        // Buffer zum ausführen von Befehlen anlegen
        let commandBuffer = metalCommandQueue.makeCommandBuffer()!
        // Buffer, welcher die Befehle zum ausfuehren Kodiert anlegen
        let  encoder = commandBuffer.makeComputeCommandEncoder()!
        
        // tell encoder to do updateTexture with drawPipeline
        encoder.setComputePipelineState(drawPipeline)
        updateTexture(renderEncoder: encoder, drawable: drawable)
        
        // tell encoder to update agents with updatePipeline
        // difference is thread count and layout
        encoder.setComputePipelineState(updatePipeline)
        let res = updateAgents(encoder: encoder, drawable: drawable)
        
        // Fertigstellen der initialisierung und buffer auf Grafikkarte schreiben
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // Warten, bis die Grafikkarte ihre Arbeit erledigt hat und Daten synchronisiert werden können
        commandBuffer.waitUntilCompleted()
        
        // Pointer auf die Daten von der Grafikkarte bekommen, dabei wird festgelegt wie die Daten eigentlich aussehen
        // -> Erstelle Pointer dessen Typ "Agent" ist und eine groesse von allen agenten hat -> also Pointer auf Array
        let agentBufferPtr = res.contents().bindMemory(to: Agent.self, capacity: MemoryLayout<Agent>.size * agents.count)

        // Die im Ram liegenden Agenten updaten bzw mit den von der Grafikkarte bezogenen Daten Überschreiben
        agents = Array(UnsafeBufferPointer(start: agentBufferPtr, count: agents.count))
    }
    
    // configure GPU execution pipeline to draw on screen #Pixel threads
    // !! Diese Funktion ist Aehnlich zu dem was auch bei Cuda passiert und nicht nur Apple stuff!!
    func updateTexture(renderEncoder : MTLComputeCommandEncoder, drawable : CAMetalDrawable) {
        // festlegen worauf gerendert / gezeichnet werden soll, hier einfach das drawable Objekt
        renderEncoder.setTexture(drawable.texture, index: 0)
        
        // aus dem Agenten Array einen Buffer erzeugen, welcher von der Grafikkarte verstanden werden kann
        let agentBuffer = makeAgentBuffer()
        // Erstellten Buffer mit den Agenten der Grafikkarte zur verfuegung zu stellen
        renderEncoder.setBuffer(agentBuffer, offset: 0, index: 0)
        
        // Festlegen mit wie vielen Threads auf der Grafikkarte an dem Problem gearbeitet werden soll
        // Wir versuchen einfach die maximale Anzahl an Threads zu nutzen
        // Aehnlich zu Cuda
        let workGroupWidth = drawPipeline.threadExecutionWidth
        let workGroupHeight = updatePipeline.maxTotalThreadsPerThreadgroup / workGroupWidth
        let threadsPerGroup = MTLSizeMake(workGroupWidth, workGroupHeight, 1)
        let threadsPerGrid = MTLSizeMake(Int(drawable.texture.width), Int(drawable.texture.height), 1)
        
        // Threads ausführen
        renderEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
    }
    
    // configure GPU execution pipeline to update the Agents #Agents threads
    // Funktion um die GPU Pipeline zu konfigurieren um die einzelnen Agenten zu updaten
    // benutzt (versucht es zumindest) für jeden Agenten einen eingenen Thread
    // Dies ist der grund warum das Programm ueberhaupt nur auf der Grafikkarte ausführbar ist, CPU waere zu langsam
    func updateAgents(encoder : MTLComputeCommandEncoder, drawable : CAMetalDrawable) -> MTLBuffer
    {
        // der erste Parameter wird mit den Agenten gefuellt
        let agentBuffer = makeAgentBuffer()
        encoder.setBuffer(agentBuffer, offset: 0, index: 0)
        
        let resBuffer = metalDevice.makeBuffer(length: MemoryLayout<Agent>.size * agents.count, options: .storageModeShared)
        encoder.setBuffer(resBuffer, offset: 0,index: 1)
        
        // Calculate the maximum threads per threadgroup based on the thread execution width.
        // Auch hier wie beim Updaten der einzelnen Pixel auf der Textur, muss festgelegt werden, wie die die Threads der
        // GPU aufgeteilt werden.
        let w = updatePipeline.threadExecutionWidth
        let h = updatePipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        
        
        let threadsPerGrid = MTLSize(width: agents.count,
                                     height: 1,
                                     depth: 1)
        
        // Threads zum arbeiten loslassen
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        return resBuffer!
    }
    
    // Funktion um einen Puffer zu erstellen, welcher von der CPU aber auch GPU genutzt werden kann
    // kopiert von StackOverflow
    func makeAgentBuffer() -> MTLBuffer? {
        var memory: UnsafeMutableRawPointer? = nil
        let agentCount: Int = agents.count
        let memory_size = agentCount * MemoryLayout<Agent>.stride
        let page_size = 0x1000
        let allocation_size = (memory_size + page_size - 1) & (~(page_size - 1))
        
        posix_memalign(&memory, page_size, allocation_size)
        memcpy(memory, &agents, allocation_size)
        
        /* storageMode:
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

// Zufaellige Punkte auf einem Kreis erzeugen
func randv_circle(min_radius : Float, max_radius : Float) ->SIMD2<Float>{
    let r2_max = max_radius * max_radius
    let r2_min = min_radius * min_radius
    let r = sqrt(Float.random(in: 0...1 ) * (r2_max - r2_min) + r2_min)
    let t = Float.random(in: 0...1) * Float.pi * 2
    return rotateRadians(v: SIMD2<Float>(r, 0),radians: t)
}



// Funktion um einen Vector um x Radianten zu Rotieren
func rotateRadians(v:SIMD2<Float>, radians:Float) -> SIMD2<Float>
{
    let ca = cos(radians);
    let sa = sin(radians);
    return SIMD2<Float>(ca*v[0] - sa*v[1], sa*v[0] + ca*v[1]);
}

// Enum um die initiale Form festzulegen, welche die Agenten auf der Oberflaeche einnehmen
enum Shape
{
    case noShape, circle, ring
}

enum Direction
{
    case random, inward, outward
}
