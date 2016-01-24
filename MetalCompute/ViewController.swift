//
//  ViewController.swift
//  MetalCompute
//
//  Created by M.Ike on 2015/12/30.
//  Copyright © 2015年 M.Ike. All rights reserved.
//

import UIKit
import MetalKit

class ViewController: UIViewController {
    private var noise: NoiseRender!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        // Metalの初期設定
        setup_metal()
        // 描画するものの初期設定
        load_assets()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func changePattern(sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            noise = NoiseRender.perlin()
        case 1:
            noise = NoiseRender.fractal()
        case 2:
            noise = NoiseRender.turbulence()
        case 3:
            noise = NoiseRender.ridgedmf()
        default:
            break
        }
        change_noise()
    }
    
    // MARK: -
    private func setup_metal() {
        if let mtkView = Render.current.setupView(self.view as? MTKView) {
            /* MTKViewの初期設定 */
            mtkView.sampleCount = 1
            mtkView.depthStencilPixelFormat = .Invalid
            
            mtkView.colorPixelFormat = .BGRA8Unorm
            mtkView.clearColor = MTLClearColorMake(0.1, 0.1, 0.1, 1)
            
            // compute shader利用時はfalse
            mtkView.framebufferOnly = false
        } else {
            assert(false)
        }
    }
    
    private func load_assets() {
        // カメラ位置を調整
        Render.current.cameraMatrix = Matrix.translation(x: 0, y: 0, z: 6)
        
        noise = NoiseRender.perlin()
        change_noise()
    }
    
    private func change_noise() {
        Render.current.renderTargets.removeAll(keepCapacity: true)
        Render.current.computeTargets.removeAll(keepCapacity: true)
        noise.modelMatrix = Matrix.translation(x: 0, y: 0, z: 0)
        Render.current.renderTargets.append(noise)
        Render.current.computeTargets.append(noise)
    }
}

