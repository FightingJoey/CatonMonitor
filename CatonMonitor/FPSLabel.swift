//
//  FPSLabel.swift
//  CatonMonitor
//
//  Created by Joey on 2021/6/11.
//

import UIKit

class WeakProxy: NSObject {
    
    weak var target: NSObjectProtocol?
    
    init(target: NSObjectProtocol) {
        self.target = target
        super.init()
    }
    
    override func responds(to aSelector: Selector!) -> Bool {
        return (target?.responds(to: aSelector) ?? false) || super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return target
    }
}

// 适合监控UI卡顿，不适合监控CPU瞬间过高导致的卡顿
class FPSLabel: UILabel {
    
    var link: CADisplayLink!
    // 记录方法执行次数
    var count: Int = 0
    // 记录上次方法执行的时间，通过link.timestamp - lastTime计算时间间隔
    var lastTime: TimeInterval = 0
    
    fileprivate let defaultSize = CGSize(width: 55, height: 20)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        if frame.size.width == 0 || frame.size.height == 0 {
            self.frame.size = defaultSize
        }
        self.layer.cornerRadius = 5
        self.clipsToBounds = true
        self.textAlignment = NSTextAlignment.center
        self.backgroundColor = UIColor.white.withAlphaComponent(0.7)

        link = CADisplayLink(target: WeakProxy.init(target: self), selector: #selector(FPSLabel.update(link:)))
        link.add(to: RunLoop.main, forMode: .common)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func update(link: CADisplayLink) {
        
        guard lastTime != 0 else {
            lastTime = link.timestamp
            return
        }
        
        count += 1
        let timePassed = link.timestamp - lastTime
        
        // 时间大于等于1秒计算一次，也就是FPSLabel刷新的间隔，不希望太频繁刷新
        guard timePassed >= 1 else {
            return
        }
        lastTime = link.timestamp
        let fps = Double(count) / timePassed
        count = 0
        
        let progress = fps / 60.0
        let color = UIColor(hue: CGFloat(0.27 * (progress - 0.2)), saturation: 1, brightness: 0.9, alpha: 1)
        
        let text = NSMutableAttributedString(string: "\(Int(round(fps))) FPS")
        text.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: NSRange(location: 0, length: text.length - 3))
        text.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.white, range: NSRange(location: text.length - 3, length: 3))
        text.addAttribute(NSAttributedString.Key.font, value: UIFont(name: "Menlo", size: 14)!, range: NSRange(location: 0, length: text.length))
        text.addAttribute(NSAttributedString.Key.font, value: UIFont(name: "Menlo", size: 14)!, range: NSRange(location: text.length - 4, length: 1))
        self.attributedText = text
    }
    
    deinit {
        link.invalidate()
    }
}
