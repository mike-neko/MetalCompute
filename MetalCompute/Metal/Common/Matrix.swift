//
//  Matrix.swift
//  MetalCompute
//
//  Created by M.Ike on 2015/12/30.
//  Copyright © 2015年 M.Ike. All rights reserved.
//

import UIKit
import simd

/* 行列周りのユーティリティ */
class Matrix {
    // 透視変換
    static func perspective(fovY fovY: Float, aspect: Float, nearZ: Float, farZ: Float) -> float4x4 {
        let yScale = 1 / simd.tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zScale = farZ / (farZ - nearZ)
        
        return float4x4([
            float4(x: xScale, y: 0, z: 0, w: 0),
            float4(x: 0, y: yScale, z: 0, w: 0),
            float4(x: 0, y: 0, z: zScale, w: 1),
            float4(x: 0, y: 0, z: -nearZ * zScale, w: 0)])
    }

    // 平行移動
    static func translation(x x: Float, y: Float, z: Float) -> float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = vector_float4(x, y, z, 1)
        return float4x4(m)
    }
    
    // 回転
    static func rotation(radians radians: Float, x: Float, y: Float, z: Float) -> float4x4 {
        let v = vector_normalize(vector_float3(x, y, z))
        let cos = simd.cosf(radians)
        let cosp = 1 - cos
        let sin = simd.sinf(radians)

        return float4x4([
            float4(
                x: cos + cosp * v.x * v.x,
                y: cosp * v.x * v.y + v.z * sin,
                z: cosp * v.x * v.z - v.y * sin,
                w: 0),
            float4(
                x: cosp * v.x * v.y - v.z * sin,
                y: cos + cosp * v.y * v.y,
                z: cosp * v.y * v.z + v.x * sin,
                w: 0),
            float4(
                x: cosp * v.x * v.z + v.y * sin,
                y: cosp * v.y * v.z - v.x * sin,
                z: cos + cosp * v.z * v.z,
                w: 0),
            float4(x: 0, y: 0, z: 0, w: 1)])
    }

    // 拡大縮小
    static func scale(x x: Float, y: Float, z: Float) -> float4x4 {
        return float4x4(diagonal: float4(x, y, z, 1))
    }
}
