# iOS性能优化之卡顿监测-Swift

最近在公司做性能优化相关的内容，领导让我把卡顿监控平台先搭建起来，于是就开始对目前主流的卡顿监测方案进行调研，在网上看到的主要有三种方案：

- 通过 CADisplayLink 监测屏幕 FPS
- 通过子线程去 ping 主线程
- 通过监控 RunLoop 的状态

下面我们来一一进行具体分析，因为公司项目是纯Swift的，所以下面的代码都是纯Swift版本的。

关于屏幕成像原理及卡顿产生的原因，请看我另一篇文章：[OC底层探究 - 性能优化](https://juejin.cn/post/6953478618467008548)

文章中的代码：[CatonMonitor](https://github.com/FightingJoey/CatonMonitor)

## CADisplayLink

CADisplayLink 是一个能让我们以和屏幕刷新率同步的频率将特定的内容画到屏幕上的定时器类。 CADisplayLink 以特定模式注册到 runloop后， 每当屏幕显示内容刷新结束的时候，runloop 就会向 CADisplayLink 指定的 target 发送一次指定的 selector 消息，CADisplayLink 类对应的 selector 就会被调用一次。

CADisplayLink 适合做界面的不停重绘，比如视频播放的时候需要不停地获取下一帧用于界面渲染。

FPS (Frames Per Second) 是图像领域中的定义，表示每秒渲染帧数，通常用于衡量画面的流畅度，每秒帧数越多，则表示画面越流畅，60fps 最佳，一般我们的APP的FPS 只要保持在 50-60之间，用户体验都是比较流畅的。

通过 CADisplayLink 监测屏幕 FPS，是通过向主线程的 RunLoop 添加一个 commonMode 的 CADisplayLink，每次屏幕刷新结束的时候都要执行 CADisplayLink 的方法，所以可以统计1s内屏幕刷新的次数，也就是FPS了。

```swift
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
```

但是简单地通过监视 FPS 是很难确定是否会出现卡顿问题，因为无法界定 FPS 在什么范围内可以确定发生卡顿了。

## 子线程Ping主线程

该方案的核心思想是：创建一个子线程通过信号量去 ping 主线程，每次 ping 时设置标记位为 YES，然后派发任务到主线程中，将标记位设置为 NO。接着子线程沉睡超时阙值时长，判断标志位是否成功设置成 NO，如果没有说明主线程发生了卡顿。

```swift
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
```

## Runloop

关于 Runloop 的原理，可以查看我另一篇文章：[OC底层探究 - Runloop](https://juejin.cn/post/6953477321042968583#heading-13)

整个 Runloop 的过程可以总结如下：

- 进入 loop
- do while 保活线程
  - 触发 timer 回调
  - 触发 source0 回调
  - 执行 block
- 进入休眠
- 等待 mach port 消息
  - 基于 port 的 source 事件
  - Timer 时间到
  - Runloop 超时
  - 被调用者唤醒
- 唤醒
- 处理消息
- 判断是否进入下一个loop

RunLoop 的目的是，当有事件要去处理时保持线程忙，当没有事件要处理时让线程进入休眠。如果 RunLoop 的线程，进入睡眠前方法的执行时间过长而导致无法进入睡眠，或者线程唤醒后接收消息时间过长而无法进入下一步的话，就可以认为是线程受阻了。如果这个线程是主线程的话，表现出来的就是出现了卡顿。

所以，如果我们要利用 RunLoop 原理来监控卡顿的话，就是要关注这两个阶段。RunLoop 在进入睡眠之前和唤醒后的两个 loop 状态定义的值，分别是 kCFRunLoopBeforeSources 和 kCFRunLoopAfterWaiting ，也就是要触发 Source0 回调和接收 mach_port 消息两个状态。

该方案的核心思想是：开辟一个子线程，然后实时计算 Runloop 的 kCFRunLoopBeforeSources 和 kCFRunLoopAfterWaiting 两个状态之间的耗时是否超过某个阀值，来断定主线程的卡顿情况。

```swift
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
```

## CPU超过了80%

这个是 [Matrix-iOS 卡顿监控](https://cloud.tencent.com/developer/article/1427933) 提到的：

> 我们也认为 CPU 过高也可能导致应用出现卡顿，所以在子线程检查主线程状态的同时，如果检测到 CPU 占用过高，会捕获当前的线程快照保存到文件中。目前微信应用中认为，单核 CPU 的占用超过了 80%，此时的 CPU 占用就过高了。

这种方式一般不能单独拿来作为卡顿监测，但可以像微信Matrix一样配合其他方式一起工作。

戴铭在 [SMCPUMonitor](https://github.com/ming1016/DecoupleDemo/blob/master/DecoupleDemo/SMCPUMonitor.m) 中做了实现，仓库中还有收集卡顿堆栈信息的代码。

```swift
// 轮询检查多个线程 cpu 情况
+ (void)updateCPU {
    thread_act_array_t threads;
    mach_msg_type_number_t threadCount = 0;
    const task_t thisTask = mach_task_self();
    kern_return_t kr = task_threads(thisTask, &threads, &threadCount);
    if (kr != KERN_SUCCESS) {
        return;
    }
    for (int i = 0; i < threadCount; i++) {
        thread_info_data_t threadInfo;
        thread_basic_info_t threadBaseInfo;
        mach_msg_type_number_t threadInfoCount = THREAD_INFO_MAX;
        if (thread_info((thread_act_t)threads[i], THREAD_BASIC_INFO, (thread_info_t)threadInfo, &threadInfoCount) == KERN_SUCCESS) {
            threadBaseInfo = (thread_basic_info_t)threadInfo;
            if (!(threadBaseInfo->flags & TH_FLAGS_IDLE)) {
                integer_t cpuUsage = threadBaseInfo->cpu_usage / 10;
                if (cpuUsage > 70) {
                    // cup 消耗大于 70 时打印和记录堆栈
                    NSString *reStr = smStackOfThread(threads[i]);
                    // 记录数据库中
                    [[[SMLagDB shareInstance] increaseWithStackString:reStr] subscribeNext:^(id x) {}];
                    NSLog(@"CPU useage overload thread stack：\n%@",reStr);
                }
            }
        }
    }
}
```

## 小结

总结下来，更推荐通过 runloop 的方式来监控卡顿，关于卡顿时，线程堆栈信息的提取，敬请期待~

在微信 Matrix 工具中，在检测线程时增加了退火算法：

为了降低检测带来的性能损耗，我们为检测线程增加了退火算法：

- 每次子线程检查到主线程卡顿，会先获得主线程的堆栈并保存到内存中（不会直接去获得线程快照保存到文件中）；
- 将获得的主线程堆栈与上次卡顿获得的主线程堆栈进行比对：
  - 如果堆栈不同，则获得当前的线程快照并写入文件中；
  - 如果相同则会跳过，并按照斐波那契数列将检查时间递增直到没有遇到卡顿或者主线程卡顿堆栈不一样。

这样，可以避免同一个卡顿写入多个文件的情况；避免检测线程遇到主线程卡死的情况下，不断写线程快照文件。

这部分内容就等我完成 Swift 版本的卡顿堆栈信息提取时再来更新吧。

## 参考文章

[iOS卡顿监测方案总结](https://juejin.cn/post/6844903944867545096#heading-0)

[Matrix-iOS 卡顿监控](https://cloud.tencent.com/developer/article/1427933)

[iOS开发高手课 | 如何利用 RunLoop 原理去监控卡顿？](https://time.geekbang.org/column/article/89494)

