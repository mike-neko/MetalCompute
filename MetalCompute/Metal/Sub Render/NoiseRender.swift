//
//  NoiseRender.swift
//  MetalCompute
//
//  Created by M.Ike on 2016/01/02.
//  Copyright © 2016年 M.Ike. All rights reserved.
//

import UIKit
import MetalKit

/* シェーダとやりとりする用 */
struct NoiseParameter {
    var frequency: Float
    var lacunarity: Float
    var gain: Float
    var amplitude: Float
    var z: Float
    var scale: Float
    var octaves: Int
    let pad1: Int = 0
}

struct TextureQuadUniforms {
    var position: float4
    var texcoord: float2
}

// MARK: -
class NoiseRender: RenderProtocol, ComputeProtocol {
    let PermSize = 256
    let TexSize = 256
    
    // Indices of vertex attribute in descriptor.
    enum VertexAttribute: Int {
        case Position = 0
        case Uniform = 1
        func index() -> Int { return self.rawValue }
    }
    enum ComputeBuffer: Int {
        case Parameter = 0
        case Perm = 1
        case Grad = 2
        func index() -> Int { return self.rawValue }
    }
    enum TextureType: Int {
        case Noise = 0
        func index() -> Int { return self.rawValue }
    }
    
    private var pipelineState: MTLRenderPipelineState! = nil
    private var depthState: MTLDepthStencilState! = nil
    
    private var renderBuffer: MTLBuffer! = nil
    private var frameUniformBuffers: [MTLBuffer] = []
    
    /* compute */
    private var computeState: MTLComputePipelineState! = nil
    
    private var permBuffer: MTLBuffer! = nil
    private var gradBuffer: MTLBuffer! = nil
    private var paramBuffer: MTLBuffer! = nil
    private var noiseTexture: MTLTexture! = nil
    
    private var threadgroupSize: MTLSize! = nil
    private var threadgroupCount: MTLSize! = nil
    
    // Uniforms
    var modelMatrix = float4x4(matrix_identity_float4x4)
    var parameter: NoiseParameter! = nil
    
    func setup(name: String, parameter: NoiseParameter) -> Bool {
        let device = Render.current.device
        let mtkView = Render.current.mtkView
        let library = Render.current.library
        
        /* render */
        guard let vertex_pg = library.newFunctionWithName("texturedQuadVertex") else { return false }
        guard let fragment_pg = library.newFunctionWithName("texturedQuadFragment") else { return false }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "noisePipeLine"
        pipelineDescriptor.sampleCount = mtkView.sampleCount
        pipelineDescriptor.vertexFunction = vertex_pg
        pipelineDescriptor.fragmentFunction = fragment_pg
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        do {
            pipelineState = try device.newRenderPipelineStateWithDescriptor(pipelineDescriptor)
        } catch {
            return false
        }
        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .Less
        depthDescriptor.depthWriteEnabled = true
        depthState = device.newDepthStencilStateWithDescriptor(depthDescriptor)
        
        // ノイズを描画したテクスチャを貼る板ポリ
        let count = 6
        let verts = [
            float4(-0.5, -0.5, 0, 1),
            float4(0.5, -0.5, 0, 1),
            float4(-0.5, 0.5, 0, 1),
            float4(0.5, -0.5, 0, 1),
            float4(-0.5, 0.5, 0, 1),
            float4(0.5, 0.5, 0, 1),
        ]
        let texs = [
            float2(0, 0),
            float2(1, 0),
            float2(0, 1),
            float2(1, 0),
            float2(0, 1),
            float2(1, 1),
        ]
        
        renderBuffer = device.newBufferWithLength(sizeof(TextureQuadUniforms) * count, options: .CPUCacheModeDefaultCache)
        let p_buf = UnsafeMutablePointer<TextureQuadUniforms>(renderBuffer.contents())
        for var i = 0; i < count; i++ {
            let uni = TextureQuadUniforms(position: verts[i], texcoord: texs[i])
            p_buf.advancedBy(i).memory = uni
        }
        
        for var i = 0; i < Render.BufferCount; i++ {
            frameUniformBuffers += [device.newBufferWithLength(sizeof(float4x4), options: .CPUCacheModeDefaultCache)]
        }
        
        
        /* compute */
        guard let pg = library.newFunctionWithName(name) else { return false }
        do {
            computeState = try device.newComputePipelineStateWithFunction(pg)
        } catch {
            return false
        }
        
        permBuffer = device.newBufferWithLength(sizeof(float4) * PermSize * PermSize, options: .CPUCacheModeDefaultCache)
        let p_perm = UnsafeMutablePointer<float4>(permBuffer.contents())
        
        var permutation = [Int](0..<PermSize * 2)
        for var i = 0; i < PermSize; i++ {
            let val = permutation[i]
            let j = Int(arc4random_uniform(UInt32(PermSize - 1)))
            permutation[i] = permutation[j]
            permutation[j] = val
        }
        for var i = 0; i < PermSize; i++ {
            permutation[i + PermSize] = permutation[i]
        }
        
        for var x = 0; x < PermSize; x++ {
            for var y = 0; y < PermSize; y++ {
                let A = permutation[x] + y
                let AA = permutation[A]
                let AB = permutation[A + 1]
                let B = permutation[x + 1] + y
                let BA = permutation[B]
                let BB = permutation[B + 1]
                
                p_perm.advancedBy(x + y * PermSize).memory
                    = float4(Float(AA) / 255, Float(AB) / 255, Float(BA) / 255, Float(BB) / 255)
            }
        }
        
        gradBuffer = device.newBufferWithLength(sizeof(float4) * PermSize, options: .CPUCacheModeDefaultCache)
        let p_grad = UnsafeMutablePointer<float4>(gradBuffer.contents())
        
        // 3次元ノイズ
        let g: [float4] = [
            float4(1, 1, 0, 0),
            float4(-1, 1, 0, 0),
            float4(1, -1, 0, 0),
            float4(-1, -1, 0, 0),
            float4(1, 0, 1, 0),
            float4(-1, 0, 1, 0),
            float4(1, 0, -1, 0),
            float4(-1, 0, -1, 0),
            float4(0, 1, 1, 0),
            float4(0, -1, 1, 0),
            float4(0, 1, -1, 0),
            float4(0, -1, -1, 0),
            float4(1, 1, 0, 0),
            float4(0, -1, 1, 0),
            float4(-1, 1, 0, 0),
            float4(0, -1, -1, 0),
        ]
        
        for var i = 0; i < PermSize; i++ {
            p_grad.advancedBy(i).memory = g[permutation[i] % 16]
        }
        
        // ノイズを書き込むテクスチャ
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
            .RGBA8Unorm, width: TexSize, height: TexSize, mipmapped: false)
        noiseTexture = device.newTextureWithDescriptor(textureDescriptor)

        paramBuffer = device.newBufferWithLength(sizeof(NoiseParameter), options: .CPUCacheModeDefaultCache)
        self.parameter = parameter
        let p_param = UnsafeMutablePointer<NoiseParameter>(paramBuffer.contents())
        p_param.memory = self.parameter

        // スレッド数は32の倍数（64-192）
        threadgroupSize = MTLSize(width: TexSize, height: TexSize, depth: 1)
        threadgroupCount = MTLSize(width: 1, height: 1, depth: 1)
        
        return true
    }
    
    func update() {
        let ren = Render.current
        
        let p = UnsafeMutablePointer<float4x4>(frameUniformBuffers[ren.activeBufferNumber].contents())
        let mat = ren.projectionMatrix * ren.cameraMatrix * modelMatrix
        p.memory = mat
    }
    
    func render(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.pushDebugGroup("Texture Quad")
        
        // Set context state.
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Set the our per frame uniforms.
        let no = Render.current.activeBufferNumber
        renderEncoder.setVertexBuffer(renderBuffer, offset: 0, atIndex: VertexAttribute.Position.index())
        renderEncoder.setVertexBuffer(frameUniformBuffers[no], offset: 0, atIndex: VertexAttribute.Uniform.index())
        renderEncoder.setFragmentTexture(noiseTexture, atIndex: TextureType.Noise.index())
       
        renderEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
        
        renderEncoder.popDebugGroup()
    }
    
    
    func compute(commandBuffer: MTLCommandBuffer) {
        parameter.z += 0.001
//        if parameter.z > 1 { parameter.z = 0 }
        
        let p_param = UnsafeMutablePointer<NoiseParameter>(paramBuffer.contents())
        p_param.memory = self.parameter

        let computeEncoder = commandBuffer.computeCommandEncoder()
        
        computeEncoder.setComputePipelineState(computeState)
        computeEncoder.setBuffer(paramBuffer, offset: 0, atIndex: ComputeBuffer.Parameter.index())
        computeEncoder.setBuffer(permBuffer, offset: 0, atIndex: ComputeBuffer.Perm.index())
        computeEncoder.setBuffer(gradBuffer, offset: 0, atIndex: ComputeBuffer.Grad.index())
        computeEncoder.setTexture(noiseTexture, atIndex: TextureType.Noise.index())
        computeEncoder.dispatchThreadgroups(threadgroupSize, threadsPerThreadgroup: threadgroupCount)
        computeEncoder.endEncoding()
    }
    
    func postRender() {
    }
    
    /* 各種ノイズ毎のレンダラー */
    static func perlin() -> NoiseRender {
        let param = NoiseParameter(
            frequency: 0, lacunarity: 0, gain: 0, amplitude: 0, z: 0.2, scale: 10, octaves: 0)
        let ren = NoiseRender()
        ren.setup("perlinNoise", parameter: param)
        return ren
    }
    
    static func fractal() -> NoiseRender {
        let param = NoiseParameter(
            frequency: 10, lacunarity: 2, gain: 0.5, amplitude: 0.5, z: 0.1, scale: 256, octaves: 8)
        let ren = NoiseRender()
        ren.setup("fractalNoise", parameter: param)
        return ren
    }
    
    static func turbulence() -> NoiseRender {
        let param = NoiseParameter(
            frequency: 1, lacunarity: 2, gain: 0.5, amplitude: 0.5, z: 0.1, scale: 256, octaves: 8)
        let ren = NoiseRender()
        ren.setup("turbulenceNoise", parameter: param)
        return ren
    }
    
    static func ridgedmf() -> NoiseRender {
        let param = NoiseParameter(
            frequency: 1, lacunarity: 2, gain: 0.5, amplitude: 0.5, z: 0.1, scale: 256, octaves: 8)
        let ren = NoiseRender()
        ren.setup("ridgedmfNoise", parameter: param)
        return ren
    }
}

