//
//  ViewController.swift
//  CatonMonitor
//
//  Created by Joey on 2021/6/11.
//

import UIKit

class ViewController: UIViewController {
        
    let fpsLabel = FPSLabel(frame: CGRect(x: 100, y: 100, width: 100, height: 20))

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(fpsLabel)
        
        CatonMonitor.shareInstance.start()
        
        RunLoopMonitor.shareInstance.start()
    }

    @IBAction func btnClicked(_ sender: Any) {
        var s = ""
        for _ in 0..<9999 {
            for _ in 0..<9999 {
                s.append("1")
            }
        }
    }
    
}

