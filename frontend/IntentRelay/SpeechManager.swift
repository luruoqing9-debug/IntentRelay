import Foundation
import AVFoundation

@MainActor
class SpeechManager: ObservableObject {
    static let shared = SpeechManager()

    @Published var currentMode: Int = 0
    @Published var currentDB: Double = 0
    @Published var isSpeaking: Bool = false
    @Published var transcriptText: String = ""
    @Published var isUserRecording: Bool = false

    // 引擎相关
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var audioBuffer: AVAudioPCMBuffer?
    private var bufferLock = NSLock()
    private var silenceStartTime: Date?

    // 后端要求的格式：16kHz 单声道
    private let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

    // VAD 参数
    private let dbThreshold: Double = 55
    private let silenceDuration: Double = 2.0
    private var consecutiveFailures = 0
    private let maxFailures = 3

    // mico=2 专用回调
    private var feedbackCallback: ((String) -> Void)?
    // mico=1 专用回调（AI 回答 → 通知面板）
    var qaCallback: ((String) -> Void)?
    // 截屏回调（语音说"截屏"时触发）
    var screenshotCallback: (() async -> Void)?

    // 后台线程安全的 VAD 状态（不用 @Published）
    private var vadIsSpeaking = false
    private var vadMode: Int = 0

    // MARK: - 公共方法

    func switchMode(to mode: Int, feedbackCallback: ((String) -> Void)? = nil) {
        if currentMode == 2 && isUserRecording {
            stopFeedbackRecording()
        }

        stopEngine()

        if mode == 2 {
            self.feedbackCallback = feedbackCallback
        }

        currentMode = mode
        vadMode = mode
        print("[Speech] 模式切换: mico=\(mode)")

        switch mode {
        case 0, 1:
            startEngine()
        case 2:
            startEngine()
            // mico=2 切到后立即开始录音
            isUserRecording = true
        default:
            break
        }
    }

    func toggleRecording() {
        if currentMode == 0 {
            // 从 mico=0 切到 mico=1，同时开始录音
            switchMode(to: 1)
            startManualRecording()
            return
        }

        if currentMode == 1 {
            if isUserRecording {
                // 停止录音，发后端调 Gemini
                stopManualRecording()
                // 录音结束后切回 mico=0
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    self.switchMode(to: 0)
                }
            }
            return
        }

        // mico=2 不允许从这里切换
    }

    // MARK: - AVAudioEngine

    private func startEngine() {
        // 模拟器没有麦克风硬件，recordPermission 永远返回 undetermined，跳过检查
        #if targetEnvironment(simulator)
        print("[Speech] 模拟器模式，跳过麦克风权限检查")
        startEngineInternal()
        #else
        // 实机：先检查并请求麦克风权限
        let currentPermission = AVAudioSession.sharedInstance().recordPermission
        switch currentPermission {
        case .granted:
            startEngineInternal()
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        print("[Speech] 麦克风权限已授予")
                        self?.startEngineInternal()
                    } else {
                        print("[Speech] 麦克风权限被拒绝")
                    }
                }
            }
        case .denied:
            print("[Speech] 麦克风权限已被拒绝，请到设置中开启")
        @unknown default:
            startEngineInternal()
        }
        #endif
    }

    private func startEngineInternal() {

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Speech] Audio session 配置错误: \(error)")
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)

        let bufferCapacity = AVAudioFrameCount(targetFormat.sampleRate * 300)
        audioBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: bufferCapacity)
        audioBuffer?.frameLength = 0

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        do {
            try engine.start()
            audioEngine = engine

            // 重置 VAD 状态，确保引擎刚启动时不会累积
            vadIsSpeaking = false
            silenceStartTime = nil
            bufferLock.lock()
            audioBuffer?.frameLength = 0
            bufferLock.unlock()

            print("[Speech] 音频引擎已启动，分贝检测运行中")
        } catch {
            print("[Speech] 音频引擎启动失败: \(error)")
        }
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter else { return }

        // 深拷贝 input buffer，避免 tap callback 回收后被系统释放
        let inputFormat = buffer.format
        let copiedBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: buffer.frameLength)!
        copiedBuffer.frameLength = buffer.frameLength
        let numInChannels = Int(inputFormat.channelCount)
        for ch in 0..<numInChannels {
            let src = buffer.floatChannelData![ch]
            let dst = copiedBuffer.floatChannelData![ch]
            memcpy(dst, src, Int(buffer.frameLength) * MemoryLayout<Float>.stride)
        }

        // 按输入帧数比例计算输出帧数，避免 converter 填满整个大 buffer
        let inputFrameLength = Int(copiedBuffer.frameLength)
        let inputSampleRate = converter.inputFormat.sampleRate
        let outputSampleRate = converter.outputFormat.sampleRate
        let expectedOutputFrames = AVAudioFrameCount(Double(inputFrameLength) * outputSampleRate / inputSampleRate)

        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: expectedOutputFrames
        )!
        var error: NSError?
        let convertStatus = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return copiedBuffer
        }

        guard convertStatus == .haveData else {
            if consecutiveFailures % 10 == 0 {
                print("[Speech] ⚠️ AVAudioConverter 失败: \(error?.localizedDescription ?? "unknown")")
            }
            consecutiveFailures += 1
            return
        }
        consecutiveFailures = 0

        guard let channelData = outputBuffer.floatChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        let numChannels = Int(outputBuffer.format.channelCount)
        let sampleRate = Int(outputBuffer.format.sampleRate)

        // 计算 RMS
        var rms: Float = 0
        for ch in 0..<numChannels {
            let ptr = channelData[ch]
            for i in 0..<frameLength {
                rms += ptr[i] * ptr[i]
            }
        }
        let totalSamples = Float(frameLength * numChannels)
        if totalSamples > 0 {
            rms = sqrt(rms / totalSamples)
        }

        let db: Double
        if rms > 0 {
            let dbRaw = 20.0 * log10(Double(rms))
            db = max(0, min(100, (dbRaw + 60.0) * (100.0 / 60.0)))
        } else {
            db = 0
        }

        DispatchQueue.main.async {
            self.currentDB = db
        }

        // VAD 逻辑（仅 mode=0）
        if vadMode == 0 {
            if db > self.dbThreshold {
                if !self.vadIsSpeaking {
                    self.vadIsSpeaking = true
                    print("[Speech] 开始说话 分贝=\(String(format: "%.1f", db))")
                }
                self.silenceStartTime = nil
            } else {
                if self.vadIsSpeaking {
                    if self.silenceStartTime == nil {
                        self.silenceStartTime = Date()
                    } else if Date().timeIntervalSince(self.silenceStartTime!) > self.silenceDuration {
                        self.vadIsSpeaking = false
                        Task { @MainActor in self.onSpeechEnd() }
                    }
                }
            }
        }

        // 累积音频：mode=0 在 VAD 触发期间累积，mode=1/2 手动录音期间累积
        if (vadMode == 0 && vadIsSpeaking) || isUserRecording {
            bufferLock.lock()
            if let buf = audioBuffer {
                let remaining = buf.frameCapacity - buf.frameLength
                let framesToCopy = min(frameLength, Int(remaining))
                if framesToCopy > 0 {
                    for ch in 0..<numChannels {
                        let src = channelData[ch]
                        let dst = buf.floatChannelData![ch]
                        memcpy(dst.advanced(by: Int(buf.frameLength)), src, framesToCopy * MemoryLayout<Float>.stride)
                    }
                    buf.frameLength += AVAudioFrameCount(framesToCopy)
                }
            }
            bufferLock.unlock()
        }
    }

    // MARK: - mode=0: VAD 说话结束

    private func onSpeechEnd() {
        isSpeaking = false
        vadIsSpeaking = false
        audioEngine?.stop()
        try? AVAudioSession.sharedInstance().setActive(false)

        guard let audioData = extractBufferToWAV() else {
            print("[Speech] 读取音频失败")
            restartDBMode()
            return
        }

        // 清空缓冲区
        bufferLock.lock()
        audioBuffer?.frameLength = 0
        bufferLock.unlock()

        print("[Speech] 说话结束，音频文件大小: \(audioData.count) bytes")
        if audioData.count <= 44 {
            print("[Speech] ⚠️ 文件太小")
        }

        Task { await sendToServer(audioData) }
    }

    private func restartDBMode() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            self.startEngine()
        }
    }

    // MARK: - mode=1: 手动录音

    private func startManualRecording() {
        bufferLock.lock()
        audioBuffer?.frameLength = 0
        bufferLock.unlock()
        isUserRecording = true
        print("[Speech] 手动录音已启动")
    }

    private func stopManualRecording() {
        isUserRecording = false
        audioEngine?.stop()
        try? AVAudioSession.sharedInstance().setActive(false)

        // 记住停止录音时的模式，避免异步期间被其他 Task 改掉
        let modeAtStop = currentMode

        guard let audioData = extractBufferToWAV() else {
            print("[Speech] 读取录音文件失败")
            return
        }

        // 计算音频时长：16kHz 单声道 16bit，每秒 32000 bytes
        let durationSeconds = Double(audioData.count - 44) / 32000.0
        print("[Speech] 手动录音结束，音频: \(audioData.count) bytes, 时长: \(String(format: "%.2f", durationSeconds))s")
        Task { await sendToServer(audioData, modeOverride: modeAtStop) }
    }

    // MARK: - mode=2: 反馈录制

    private func stopFeedbackRecording() {
        isUserRecording = false
        audioEngine?.stop()
        try? AVAudioSession.sharedInstance().setActive(false)

        guard let audioData = extractBufferToWAV() else {
            print("[Speech] 读取反馈录音失败，重置状态")
            feedbackCallback = nil
            return
        }

        print("[Speech] 反馈录音结束，音频文件大小: \(audioData.count) bytes")
        Task { await sendFeedbackToServer(audioData) }
    }

    // MARK: - 提取 WAV

    private func extractBufferToWAV() -> Data? {
        bufferLock.lock()
        guard let buf = audioBuffer else {
            bufferLock.unlock()
            return nil
        }
        let frameLength = Int(buf.frameLength)
        guard frameLength > 0 else {
            bufferLock.unlock()
            return nil
        }

        let copyFormat = buf.format
        let copied = AVAudioPCMBuffer(pcmFormat: copyFormat, frameCapacity: AVAudioFrameCount(frameLength))!
        copied.frameLength = buf.frameLength
        let numCh = Int(copyFormat.channelCount)
        for ch in 0..<numCh {
            let src = buf.floatChannelData![ch]
            let dst = copied.floatChannelData![ch]
            memcpy(dst, src, frameLength * MemoryLayout<Float>.stride)
        }
        bufferLock.unlock()

        return writePCMToWAV(buffer: copied)
    }

    private func writePCMToWAV(buffer: AVAudioPCMBuffer) -> Data? {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let sampleRate = buffer.format.sampleRate
        let channels = Int(buffer.format.channelCount)
        let bitDepth: UInt16 = 16

        let pcmSize = frameLength * channels * MemoryLayout<Int16>.size
        var pcmData = Data(count: pcmSize)
        pcmData.withUnsafeMutableBytes { ptr in
            let int16Ptr = ptr.baseAddress!.assumingMemoryBound(to: Int16.self)
            let floatPtr = buffer.floatChannelData![0]
            for i in 0..<frameLength {
                let clamped = max(-1.0, min(1.0, floatPtr[i]))
                int16Ptr[i] = Int16(clamped * 32767.0)
            }
        }

        let chunkSize = UInt32(36 + pcmData.count)
        let sampleRateUInt32 = UInt32(sampleRate)
        let byteRate = sampleRateUInt32 * UInt32(channels) * (UInt32(bitDepth) / 8)
        let dataSize = UInt32(pcmData.count)

        var wavData = Data()
        wavData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        wavData.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
        wavData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        wavData.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: sampleRateUInt32.littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(channels * 2).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: bitDepth.littleEndian) { Data($0) })
        wavData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        wavData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(pcmData)

        return wavData
    }

    // MARK: - 发送后端

    private func sendToServer(_ audioData: Data, modeOverride: Int? = nil) async {
        let mode = modeOverride ?? currentMode
        print("[Speech] 发送音频到后端: \(audioData.count) bytes, 当前模式: mico=\(mode)")
        do {
            // 第一步：所有模式都先调 speech_transcribe 拿到文本
            let text = try await BackendAPI.shared.transcribeAudio(audioData)
            transcriptText = text
            print("[Speech] ✅ 识别成功: \"\(text)\"")

            // 检测截屏关键词
            if text.contains("截屏") || text.contains("截图") {
                print("[Speech] 检测到截屏指令，触发截屏")
                await screenshotCallback?()
                return
            }

            // 第二步：根据模式调不同接口
            switch mode {
            case 0:
                // mico=0: VLM 意图分析，存记忆，不弹通知
                try await BackendAPI.shared.vlmAnalysis(
                    transcriptText: text,
                    triggerTypes: ["语音输入触发"]
                )
                print("[Speech] ✅ VLM 分析完成，已存入记忆")

            case 1:
                // mico=1: LLM 对话，返回 AI 回答 → 弹通知面板
                let qaResult = try await BackendAPI.shared.qaSwitchTest(question: text)
                if qaResult.success && !qaResult.answer.isEmpty {
                    print("[Speech] ✅ AI 回答: \(qaResult.answer)")
                    qaCallback?(qaResult.answer)
                }

            case 2:
                // mico=2: 用户反馈，调整权重
                let fbResult = try await BackendAPI.shared.userFeedback(feedback: text)
                if fbResult.success {
                    print("[Speech] ✅ 反馈已处理: \(fbResult.analysis)")
                    feedbackCallback?(text)
                }

            default:
                break
            }
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures >= maxFailures {
                print("[Speech] ❌ 连续失败 \(consecutiveFailures)/\(maxFailures)")
            } else {
                print("[Speech] ⚠️ 识别失败 (\(consecutiveFailures)/\(maxFailures)): \(error)")
            }
        }

        startEngine()
    }

    private func sendFeedbackToServer(_ audioData: Data) async {
        print("[Speech] 发送反馈音频到后端: \(audioData.count) bytes")
        do {
            // 第一步：语音识别
            let text = try await BackendAPI.shared.transcribeAudio(audioData)
            transcriptText = text
            print("[Speech] ✅ 反馈识别成功: \"\(text)\"")

            // 第二步：调 /user_feedback 提交反馈
            let fbResult = try await BackendAPI.shared.userFeedback(feedback: text)
            if fbResult.success {
                print("[Speech] ✅ 反馈已处理: \(fbResult.analysis)")
            }
        } catch {
            print("[Speech] 反馈处理失败: \(error)")
        }

        feedbackCallback = nil
        switchMode(to: 0)
    }

    // MARK: - 停止

    private func stopEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
        isSpeaking = false
        vadIsSpeaking = false
        currentDB = 0
        isUserRecording = false
        bufferLock.lock()
        audioBuffer?.frameLength = 0
        bufferLock.unlock()
    }
}
