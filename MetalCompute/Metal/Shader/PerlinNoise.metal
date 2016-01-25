//
//  PerlinNoise.metal
//  MetalCompute
//
//  Created by M.Ike on 2015/12/31.
//  Copyright © 2015年 M.Ike. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

// ノイズを生成してテクスチャに書き込むシェーダ

struct NoiseParameter {
    float       frequency;
    float       lacunarity;
    float       gain;
    float       amplitude;
    float       z;
    float       scale;
    int         octaves;
    int         size;
};

// テクスチャのサイズ
static constant int TEX_SIZE = 256;

static float3 fade(float3 t) {
    // 6t^5 - 15t^4 + 10t^3
    return t * t * t * (t * (t * 6 - 15) + 10);
}

static float4 perm2d(constant float4* texture, float2 uv) {
    return texture[int(uv.x) + int(uv.y) * TEX_SIZE];
}

static float gradperm(constant float4* texture, float x, float3 p) {
    float3 g = texture[(int)(x * TEX_SIZE) % TEX_SIZE].rgb;
    return dot(g, p);
}

static float inoise(constant float4* perm, constant float4* grad, float3 p) {
    float3 P = float3(fmod(((float)(int)p.x), TEX_SIZE),
                      fmod(((float)(int)p.y), TEX_SIZE),
                      fmod(((float)(int)p.z), TEX_SIZE));
    p = float3(p.x - float(int(p.x)),
               p.y - float(int(p.y)),
               p.z - float(int(p.z)));
    float3 f = fade(p);
    const float one = 1.f / TEX_SIZE;
    float4 AA = perm2d(perm, P.xy) + float4(P.z / TEX_SIZE, P.z / TEX_SIZE, P.z / TEX_SIZE, P.z / TEX_SIZE);
    return mix(mix(mix(gradperm(grad, AA.x, p),
                       gradperm(grad, AA.z, p + float3(-1, 0, 0)),
                       f.x),
                   mix(gradperm(grad, AA.y, p + float3(0, -1, 0)),
                       gradperm(grad, AA.w, p + float3(-1, -1, 0)),
                       f.x),
                   f.y),
                
                mix(mix(gradperm(grad, AA.x + one, p + float3(0, 0, -1)),
                        gradperm(grad, AA.z + one, p + float3(-1, 0, -1)),
                        f.x),
                    mix(gradperm(grad, AA.y + one, p + float3(0, -1, -1)),
                        gradperm(grad, AA.w + one, p + float3(-1, -1, -1)),
                        f.x),
                    f.y),
                f.z);
}

kernel void perlinNoise(const device NoiseParameter& param [[ buffer(0) ]],
                        constant float4* permData [[ buffer(1) ]],
                        constant float4* gradData [[ buffer(2) ]],
                        texture2d<float, access::write> out  [[ texture(0) ]],
                        uint2 id [[ thread_position_in_grid ]]) {
    float3 pos = float3(id.x / param.scale, id.y / param.scale, param.z);
    float n = inoise(permData, gradData, pos) + 0.5f;
    float4 color = float4(n, n, n, 1);
    out.write(color, id);
}

kernel void fractalNoise(const device NoiseParameter& param [[ buffer(0) ]],
                         constant float4* permData [[ buffer(1) ]],
                         constant float4* gradData [[ buffer(2) ]],
                         texture2d<float, access::write> out  [[ texture(0) ]],
                         uint2 id [[ thread_position_in_grid ]]) {
    float3 pos = float3(id.x / param.scale, id.y / param.scale, param.z);
    
    float freq = param.frequency;
    float amp = param.amplitude;
    float n = 0;
    for(int i = 0; i < param.octaves; i++) {
        n += inoise(permData, gradData, pos * freq) * amp;
        freq *= param.lacunarity;
        amp *= param.gain;
    }
    float4 color = float4(n, n, n, 1);
    out.write(color, id);
}

kernel void turbulenceNoise(const device NoiseParameter& param [[ buffer(0) ]],
                            constant float4* permData [[ buffer(1) ]],
                            constant float4* gradData [[ buffer(2) ]],
                            texture2d<float, access::write> out  [[ texture(0) ]],
                            uint2 id [[ thread_position_in_grid ]]) {
    float3 pos = float3(id.x / param.scale, id.y / param.scale, param.z);
    float freq = param.frequency;
    float amp = param.amplitude;
    float n = 0;
    for(int i = 0; i < param.octaves; i++) {
        n += abs(inoise(permData, gradData, pos * freq) * amp);
        freq *= param.lacunarity;
        amp *= param.gain;
    }
 
    float4 color = float4(n, n, n, 1);
    out.write(color, id);
}

static float ridge(float h, float offset) {
    h = offset - abs(h);
    h *= h;
    return h;
}

kernel void ridgedmfNoise(const device NoiseParameter& param [[ buffer(0) ]],
                          constant float4* permData [[ buffer(1) ]],
                          constant float4* gradData [[ buffer(2) ]],
                          texture2d<float, access::write> out  [[ texture(0) ]],
                          uint2 id [[ thread_position_in_grid ]]) {
    float3 pos = float3(id.x / param.scale, id.y / param.scale, param.z);
    float freq = param.frequency;
    float amp = param.amplitude;
    float sum = 0;
    float prev = 1;
    float offset = 1;
    for(int i = 0; i < param.octaves; i++) {
        float n = ridge(inoise(permData, gradData, pos * freq), offset);
        sum += n * amp * prev;
        freq *= param.lacunarity;
        amp *= param.gain;
    }
    
    float4 color = float4(sum, sum, sum, 1);
    out.write(color, id);
}

