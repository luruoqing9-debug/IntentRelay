//
//  BroadcastButtonView.swift
//
//  Created by 蒋招衢 on 2025/7/1.
//

import SwiftUI
import ReplayKit
import Foundation

// ============ 以下代码仅供测试使用，之后需要删除 ============
// 测试用 WebSocket 客户端，用于直接发送屏幕截图到后端
/*
class TestScreenshotSender: ObservableObject {
    private var wsTask: URLSessionWebSocketTask?
    private var timer: Timer?
    @Published var isSending = false
    @Published var frameCount = 0

    func start() {
        guard !isSending else { return }
        isSending = true
        frameCount = 0

        // 连接到后端 WebSocket
        let url = URL(string: "ws://refinity-intentrelaystream.pub.hsuni.top:15902/stream")!
        wsTask = URLSession.shared.webSocketTask(with: url)
        wsTask?.resume()
        print("[TestSender] WebSocket 已连接")

        // 每 1 秒截取一次屏幕并发送
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.captureAndSend()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        isSending = false
        print("[TestSender] 已停止，共发送 \(frameCount) 帧")
    }

    // 截取当前屏幕并转为 JPEG 发送
    // 注：visionOS 用 Metal 渲染，直接截图可能拿到空白画面
    // 所以测试用直接生成带时间戳的色块图，验证 WebSocket 链路即可
    private func captureAndSend() {
        guard let wsTask = wsTask else { return }

        // 生成一张 1920x1080 的测试图（随机背景色 + 帧号）
        let size = CGSize(width: 1920, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // 随机背景色，方便肉眼区分每一帧
            let hue = CGFloat(self.frameCount) * 0.07.truncatingRemainder(dividingBy: 1.0)
            UIColor(hue: hue, saturation: 0.3, brightness: 0.8, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // 画帧号文字
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 120, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let text = "Frame #\(self.frameCount + 1)"
            let textSize = text.size(withAttributes: attributes)
            text.draw(in: CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            ), withAttributes: attributes)
        }

        // 转为 JPEG（60% 质量，保持与广播扩展一致）
        guard let jpegData = image.jpegData(compressionQuality: 0.6) else {
            print("[TestSender] JPEG 转换失败")
            return
        }

        // 拼接 "IMG" 前缀发送
        let prefixData = "IMG".data(using: .utf8)!
        let message = URLSessionWebSocketTask.Message.data(prefixData + jpegData)

        wsTask.send(message) { error in
            if let error = error {
                print("[TestSender] 发送失败: \(error.localizedDescription)")
            } else {
                self.frameCount += 1
                print("[TestSender] 已发送帧 #\(self.frameCount), 大小: \(jpegData.count) bytes")
            }
        }
    }
}
*/
// ============ 以上代码仅供测试使用，之后需要删除 ============

struct RecordContentView: View {
    @State var isShow:Bool = false
    @State var isSharePlaying:Bool = false

    // ============ 以下代码仅供测试使用，之后需要删除 ============
    // @StateObject private var testSender = TestScreenshotSender()
    // ============ 以上代码仅供测试使用，之后需要删除 ============

    // 定义需要监听的 CFNotificationCenter 通知名称（可以动态扩展）
    private let notificationNames: [CFString] = [
        "group.IntentRelay.hasStart" as CFString,
        "group.IntentRelay.hasEnd" as CFString,
        "group.IntentRelay.hellohello!" as CFString
        // 可以根据需要添加更多通知名称
    ]

    var body: some View {
        ZStack{
            VStack{
                Button(action:{
                    isShow = false
                    Task{
                        try! await Task.sleep(nanoseconds: 100_000_000) // 100 毫秒的延迟，确保每次都能打开系统控制中心
                        isShow = true
                    }
                }){
                    VStack{
                        Image(systemName: "shareplay")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(isSharePlaying ? .black : .white) // 图标颜色
                            .frame(width: 50, height: 50) // 图标大小
                    }
                    .frame(width: 90,height: 90)
                    .background(isSharePlaying ? .white : .clear)
                    .background(.thinMaterial)
                    .cornerRadius(50)
                }
                .clipShape(Circle()) // 将按钮裁剪为圆形
                .buttonStyle(PlainButtonStyle())

                Text("Share view with AI")
                    .foregroundColor(.secondary)

                // ============ 以下按钮仅供测试使用，之后需要删除 ============
                // Button(action: {
                //     if testSender.isSending {
                //         testSender.stop()
                //     } else {
                //         testSender.start()
                //     }
                // }) {
                //     VStack {
                //         Image(systemName: testSender.isSending ? "stop.circle.fill" : "play.circle.fill")
                //             .resizable()
                //             .scaledToFit()
                //             .foregroundColor(.yellow)
                //             .frame(width: 40, height: 40)
                //         Text(testSender.isSending ? "停止测试" : "测试：1秒/帧")
                //             .font(.caption)
                //             .foregroundColor(.yellow)
                //     }
                //     .frame(width: 120, height: 80)
                //     .background(.ultraThinMaterial)
                //     .cornerRadius(16)
                // }
                // .buttonStyle(PlainButtonStyle())
                // ============ 以上按钮仅供测试使用，之后需要删除 ============
            }

            if(isShow){
                BroadcastButtonView()
                    .frame(width:80, height: 80)
                    .opacity(0)
            }
        }
        .onAppear {
            addCFObservers()
            addGenericNotificationCenterObserver()
        }
        .onDisappear {
            removeCFObservers()
            removeGenericNotificationCenterObserver()
        }
    }
    
    // 添加 CFNotificationCenter 观察者
    private func addCFObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in notificationNames {
            CFNotificationCenterAddObserver(center,nil,cfNotificationCallback,name,nil,.deliverImmediately)
        }
    }

    // 移除 CFNotificationCenter 观察者
    private func removeCFObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in notificationNames {
            CFNotificationCenterRemoveObserver(center, nil, CFNotificationName(name), nil)
        }
    }

    // 添加通用的 NotificationCenter 观察者
    private func addGenericNotificationCenterObserver() {
        NotificationCenter.default.addObserver(forName: .cfNotificationReceived, object: nil, queue: .main) { notification in
            guard let userInfo = notification.userInfo,
                  let name = userInfo["name"] as? String else { return }

            // 使用 switch 语句处理不同的通知名
            switch name {
            case "group.IntentRelay.hasStart":
                isSharePlaying = true
                BroadcastManager.shared.isAddingUI = true
                Task {
                    try await Task.sleep(nanoseconds: 10_000)
                    await MainActor.run {
                        BroadcastManager.shared.isAddingUI = false
                    }
                }
            case "group.IntentRelay.hasEnd":
                isSharePlaying = false
                BroadcastManager.shared.isHidingUI = true
                Task {
                    try await Task.sleep(nanoseconds: 10_000)
                    await MainActor.run {
                        BroadcastManager.shared.isHidingUI = false
                    }
                }
            default:
                handleDynamicNotification(name: name, userInfo: userInfo["userInfo"] as? [AnyHashable: Any])
            }
        }
    }

    // 处理动态的通知名称
    private func handleDynamicNotification(name: String, userInfo: [AnyHashable: Any]?) {
        // 定义一个映射字典，将通知名称映射到对应的操作
        let notificationActionMap: [String: () -> Void] = [
            "group.IntentRelay.hellohello!": {
                print("Handling 'hellohello!' notification")
            },
            // 可以继续添加更多的映射
        ]

        // 查找并执行对应的操作
        if let action = notificationActionMap[name] {
            action()
        } else {
            print("No action mapped for notification: \(name)")
        }
    }

    // 移除通用的 NotificationCenter 观察者
    private func removeGenericNotificationCenterObserver() {
        NotificationCenter.default.removeObserver(self, name: .cfNotificationReceived, object: nil)
    }
}


struct BroadcastButtonView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        // 创建一个容器 UIView
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))

        // 自定义外观（例如圆形按钮背景）
        containerView.layer.cornerRadius = 40
        containerView.backgroundColor = UIColor.white
        containerView.clipsToBounds = true

        let broadcastPickerView = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        broadcastPickerView.preferredExtension = "com.ZhaoquJiang.RefinityAI.IntentRelay.IntentRelayRecorder"
        broadcastPickerView.showsMicrophoneButton = true

        DispatchQueue.main.async {
            for subview in broadcastPickerView.subviews {
                let b = subview as! UIButton
                // b.setImage(UIImage(named : "nil"), for: .normal)
                b.frame = containerView.bounds
                b.backgroundColor = .clear // 确保背景透明
                b.sendActions(for: .touchUpInside) // 触发系统按钮点击事件
                containerView.addSubview(b)
                break
            }
        }
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the view if needed
    }
}


// 全局的回调函数
func cfNotificationCallback(center: CFNotificationCenter?,
                            observer: UnsafeMutableRawPointer?,
                            name: CFNotificationName?,
                            object: UnsafeRawPointer?,
                            userInfo: CFDictionary?) {
    guard let name = name else { return }
    let notificationName = name.rawValue as String
    
    // 在主线程中发送统一的通知，包含原始通知名和 userInfo
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .cfNotificationReceived, object: nil, userInfo: [
            "name": notificationName,
            "userInfo": userInfo as? [AnyHashable: Any] ?? [:]
        ])
    }
}

// 扩展 Notification.Name 以包含通用通知
extension Notification.Name {
    static let cfNotificationReceived = Notification.Name("CFNotificationReceived")
}

#Preview(windowStyle: .automatic) {
    RecordContentView()
        .environment(AppModel())
}

