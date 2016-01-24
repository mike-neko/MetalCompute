//
//  TextureQuad.metal
//  MetalCompute
//
//  Created by M.Ike on 2016/01/01.
//  Copyright © 2016年 M.Ike. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

// テクスチャ付きの板ポリ描画用シェーダ

struct ShaderInOut {
    float4      position        [[ position ]];
    float2      texcoord        [[ user(texturecoord) ]];
};

vertex ShaderInOut texturedQuadVertex(const device ShaderInOut* in [[ buffer(0) ]],
                                      constant float4x4& mvp [[ buffer(1) ]],
                                      uint vid [[ vertex_id ]]) {
    ShaderInOut out;
    out.position = mvp * in[vid].position;
    out.texcoord = in[vid].texcoord;
    return out;
}

fragment float4 texturedQuadFragment(ShaderInOut in [[ stage_in ]],
                                    texture2d<float> texture [[ texture(0) ]]) {
    constexpr sampler quadSampler;
    float4 color = texture.sample(quadSampler, in.texcoord);
    return color;
}
