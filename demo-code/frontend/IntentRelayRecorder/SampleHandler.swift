import ReplayKit
import Photos
import CoreImage

let frameInterval:Double = 1.0

class SampleHandler: RPBroadcastSampleHandler {

    let center = CFNotificationCenterGetDarwinNotifyCenter()
    var wsClient: WebSocketClient?
    
    // 记录上一次保存照片的时间
    var lastSaveTime: CMTime = CMTime.zero
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
        super.broadcastStarted(withSetupInfo: setupInfo)
        CFNotificationCenterPostNotification(center, CFNotificationName("group.IntentRelay.hasStart" as CFString), nil, nil, true) //通知主app开始录制
        print("Broadcast started.")
        //推送视频帧
        wsClient = WebSocketClient(url: URL(string: "ws://refinity-intentrelaystream.pub.hsuni.top:15902/stream")!)
    }
    
    override func broadcastPaused() {
        // User has requested to pause the broadcast. Samples will stop being delivered.
        CFNotificationCenterPostNotification(center, CFNotificationName("group.IntentRelay.hasEnd" as CFString), nil, nil, true)
        print("Broadcast paused.")
    }
    
    override func broadcastResumed() {
        // User has requested to resume the broadcast. Samples delivery will resume.
        CFNotificationCenterPostNotification(center, CFNotificationName("group.IntentRelay.hasStart" as CFString), nil, nil, true)
        print("Broadcast resumed.")
    }
    
    override func broadcastFinished() {
        // User has requested to finish the broadcast.
        super.broadcastFinished()
        CFNotificationCenterPostNotification(center, CFNotificationName("group.IntentRelay.hasEnd" as CFString), nil, nil, true)
        print("Broadcast finished.")
        wsClient?.close()
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case RPSampleBufferType.video:
            // Handle video sample buffer
#if false
            print("a video buffer received")
#endif
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            // 设置每秒执行一次传输帧
            if CMTimeSubtract(presentationTime, lastSaveTime).seconds >= frameInterval {
                lastSaveTime = presentationTime
                if let jpegData = jpegData(from: sampleBuffer) {
                    print("send a buffer data")
                    wsClient?.send(data: jpegData, prefix: "IMG")
                }
            }
            break
        case RPSampleBufferType.audioApp:
            // Handle audio sample buffer for app audio
            break
        case RPSampleBufferType.audioMic:
            // Handle audio sample buffer for mic audio
            if let pcmData = pcmData(from: sampleBuffer) {
                wsClient?.send(data: pcmData, prefix: "AUD")
            }
            break
        @unknown default:
            // Handle other sample buffer types
            fatalError("Unknown type of sample buffer")
        }
    }

    //将 CMSampleBuffer 转化为 jpeg 数据
    func jpegData(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.6)
    }
    
    // 将 CMSampleBuffer 转化为 pcm数据
    func pcmData(from sampleBuffer: CMSampleBuffer) -> Data? {
#if false
        if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
            print("Sample rate: \(asbd.mSampleRate)")
            print("Channels: \(asbd.mChannelsPerFrame)")
            print("Format ID: \(asbd.mFormatID)")
            print("Bits per channel: \(asbd.mBitsPerChannel)")
            print("Bytes per frame: \(asbd.mBytesPerFrame)")
            print("Is float: \((asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0)")
        }
#endif
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        if status == kCMBlockBufferNoErr, let pointer = dataPointer {
            return Data(bytes: pointer, count: length)
        }

        return nil
    }
    
    // 将 CVPixelBuffer 转换为 UIImage 并保存到相册
    func savePixelBufferToPhotoLibrary(pixelBuffer: CVPixelBuffer) {
        // 使用 CIImage 创建 UIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("无法创建 CGImage。")
            return
        }
        let image = UIImage(cgImage: cgImage)
        
        // 请求相册权限
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                // 保存图片到相册
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    if success {
                        print("成功保存一张照片到相册。")
                    } else {
                        if let error = error {
                            print("保存照片失败: \(error.localizedDescription)")
                        } else {
                            print("保存照片失败，未知错误。")
                        }
                    }
                }
            } else {
                print("未获得相册访问权限。")
            }
        }
    }
}

class WebSocketClient {
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var session: URLSession = URLSession(configuration: .default)
    private var isConnected = false
    private var retryCount = 0
    private let maxRetries = 5
    private let reconnectDelay: TimeInterval = 2.0

    private var pingTimer: Timer?

    init(url: URL) {
        self.url = url
        connect()
    }

    func connect() {
        task = session.webSocketTask(with: url)
        task?.resume()
        isConnected = true
        listen()
        startPing()
        print("WebSocket 连接中...")
    }

    func reconnect() {
        guard retryCount < maxRetries else {
            print("已达到最大重连次数")
            return
        }

        isConnected = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        retryCount += 1
        DispatchQueue.global().asyncAfter(deadline: .now() + reconnectDelay) {
            print("尝试重连 (\(self.retryCount))...")
            self.connect()
        }
    }

    func send(data: Data, prefix: String) {
        guard isConnected else {
            print("WebSocket 未连接，无法发送数据")
            return
        }

        let prefixData = prefix.data(using: .utf8)!
        let message = URLSessionWebSocketTask.Message.data(prefixData + data)

        task?.send(message) { error in
            if let error = error {
                print("发送失败：\(error.localizedDescription)")
                self.reconnect()
            }
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            switch result {
            case .success(let message):
                // 如果有服务器消息响应
                print("收到消息：\(message)")
                self?.retryCount = 0
                self?.listen() // 继续监听
            case .failure(let error):
                print("监听失败：\(error)")
                self?.reconnect()
            }
        }
    }

    private func startPing() {
        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }

    private func sendPing() {
        task?.sendPing { [weak self] error in
            if let error = error {
                print("Ping失败：\(error.localizedDescription)")
                self?.reconnect()
            } else {
                print("Ping成功")
            }
        }
    }

    func close() {
        isConnected = false
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        print("WebSocket 已关闭")
    }
}
