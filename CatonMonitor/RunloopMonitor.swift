//
//  RunloopMonitor.swift
//  CatonMonitor
//
//  Created by Joey on 2021/6/11.
//

import Foundation

class RunLoopMonitor {
    static let shareInstance = RunLoopMonitor()
    
    var timeoutCount = 0
    var runloopObserver: CFRunLoopObserver?
    var runLoopActivity: CFRunLoopActivity?
    var dispatchSemaphore: DispatchSemaphore?
    
    private init() {}
    
    func start() {
        
        guard runloopObserver == nil else {
            return
        }

        let uptr = Unmanaged.passRetained(self).toOpaque()
        let vptr = UnsafeMutableRawPointer(uptr)
        var content = CFRunLoopObserverContext(version: 0, info: vptr, retain: nil, release: nil, copyDescription: nil)
        
        // 创建观察者
        runloopObserver = CFRunLoopObserverCreate(kCFAllocatorDefault, CFRunLoopActivity.allActivities.rawValue, true, 0, observeCallBack(), &content)
        // 将观察者添加到主线程runloop的common模式下的观察中
        CFRunLoopAddObserver(CFRunLoopGetMain(), runloopObserver, CFRunLoopMode.commonModes)
        // 初始化信号量为0
        dispatchSemaphore = DispatchSemaphore(value:0)
        
        DispatchQueue.global().async {
            // 子线程开启一个持续的loop用来进行监控
            while(true) {
                // 等待时间250毫秒
                let st = self.dispatchSemaphore?.wait(timeout:DispatchTime.now() + .milliseconds(50))
                // st == .timeOut 超时了，表示发生卡顿了
                if st == .timedOut {
                    if self.runloopObserver == nil {
                        self.dispatchSemaphore = nil
                        self.runLoopActivity = nil
                        self.timeoutCount = 0
                        return
                    }
                    // BeforeSources 和 AfterWaiting 这两个状态能够检测到是否卡顿
                    if self.runLoopActivity == .afterWaiting || self.runLoopActivity == .beforeSources {
                        // 连续监测到三次超时
                        self.timeoutCount += 1
                        if self.timeoutCount < 3 {
                            continue
                        }
                        DispatchQueue.global().async {
                            print("卡顿了")
                            // 捕获堆栈进行上报
                        }
                    }
                }
                self.timeoutCount = 0
            }
        }
    }
    
    func end() {
        guard let _ = runloopObserver else {
            return
        }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), runloopObserver, CFRunLoopMode.commonModes)
        runloopObserver = nil
    }
    
    deinit {
        end()
    }
    
    private func observeCallBack() -> CFRunLoopObserverCallBack {
        return{ (observer, activity, context)in
            let weakSelf = Unmanaged<RunLoopMonitor>.fromOpaque(context!).takeUnretainedValue()
            // 获取到当前的activity
            weakSelf.runLoopActivity = activity
            // 完成了一次观察，添加信号量
            weakSelf.dispatchSemaphore?.signal()
        }
    }
}
