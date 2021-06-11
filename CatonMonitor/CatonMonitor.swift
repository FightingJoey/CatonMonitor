//
//  CatonMonitor.swift
//  CatonMonitor
//
//  Created by Joey on 2021/6/11.
//

import Foundation

public class CatonMonitor {
    
    static let shareInstance = CatonMonitor()
    
    private var isMonitoring = false
    private let semaphore = DispatchSemaphore(value: 0)

    public func start() {
        if isMonitoring { return }
        isMonitoring = true

        DispatchQueue.global().async { [weak self] in
            guard let strongSelf = self else {
                return
            }
            while strongSelf.isMonitoring {
                var timeout = true
                
                DispatchQueue.main.async {
                    // 如果主线程没有卡顿，就会执行
                    timeout = false
                    self?.semaphore.signal()
                }

                Thread.sleep(forTimeInterval: 0.05)

                if timeout {
                    print("卡顿了")
                }
                self?.semaphore.wait()
            }
        }
    }

    public func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
    }
    
    deinit {
        stop()
    }
}
