import SwiftUI
import Observation

@Observable
class AINotificationViewModel {
    var message: String? = nil
    var isShowing = false
    
    // 生成状态
    var isGeneratingImage = false
    var generatedImage: UIImage? = nil
    var isGeneratingModel = false
    var isModelReady = false
    var modelURL: String? = nil

    // AI 回答（语音反馈结果）
    var aiAnswer: String? = nil
    var isFetchingAnswer = false

    // 评价状态
    var isEvaluating = false
    
    private var autoDismissWorkItem: DispatchWorkItem? = nil
    private var nextNotificationWorkItem: DispatchWorkItem? = nil
    private var currentNotificationID = UUID()
    
    private let mockMessages = [
        "I noticed you have specific requirements for the streamlined frame, so I prepared relevant visual references.",
        "Based on your material preference mentioned earlier, I generated a new matte-texture model suggestion.",
        "I detected your concern about garage space, and recommend checking this semi-open design concept."
    ]
    
    func triggerNotification() {
        cancelAutoDismiss()
        nextNotificationWorkItem?.cancel()
        currentNotificationID = UUID()
        
        withAnimation(.spring()) {
            message = mockMessages.randomElement()
            isShowing = true
        }
        
        // 10秒后自动消失
        scheduleAutoDismiss(for: currentNotificationID)
    }
    
    func dismiss() {
        cancelAutoDismiss()
        withAnimation {
            isShowing = false
            resetState()
        }
    }
    
    func stopAutoDismiss() {
        cancelAutoDismiss()
    }
    
    private func resetState() {
        isGeneratingImage = false
        isGeneratingModel = false
        generatedImage = nil
        isModelReady = false
        modelURL = nil
        aiAnswer = nil
        isFetchingAnswer = false
        isEvaluating = false
    }
    
    private func scheduleNextNotification() {
        // 如果当前没有显示通知，则在 20 秒后再次触发
        nextNotificationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            if let self = self, !self.isShowing {
                self.triggerNotification()
            }
        }
        nextNotificationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0, execute: workItem)
    }

    private func scheduleAutoDismiss(for notificationID: UUID) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isShowing, self.currentNotificationID == notificationID else { return }
            self.dismiss()
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: workItem)
    }

    private func cancelAutoDismiss() {
        autoDismissWorkItem?.cancel()
        autoDismissWorkItem = nil
    }

    // MARK: - 语音反馈 → 前端本地录音

    @MainActor
    func toggleEvaluation() {
        // 如果已经在录音中，停止录音（切回 mode=0），后端自动处理反馈
        if isEvaluating {
            withAnimation {
                isEvaluating = false
            }
            SpeechManager.shared.switchMode(to: 0)
            return
        }

        stopAutoDismiss()
        withAnimation {
            isEvaluating = true
        }

        print("[语音反馈] 开始录音")

        SpeechManager.shared.switchMode(to: 2, feedbackCallback: { [weak self] text in
            Task { @MainActor in
                self?.aiAnswer = "Feedback processed: \(text)"
                self?.isEvaluating = false
            }
        })
    }

    // MARK: - 图片生成 → 调 /generate_from_answer

    @MainActor
    func startImageGeneration() {
        stopAutoDismiss()
        isGeneratingImage = true

        Task { [weak self] in
            do {
                let response = try await BackendAPI.shared.generateFromAnswer(answer: self?.aiAnswer)

                if response.success, !response.imagePaths.isEmpty {
                    let imageURL = response.imagePaths[0]
                    if let image = await BackendAPI.shared.downloadImage(from: imageURL) {
                        await MainActor.run {
                            withAnimation {
                                self?.isGeneratingImage = false
                                self?.generatedImage = image
                            }
                        }
                    } else {
                        await MainActor.run {
                            withAnimation {
                                self?.isGeneratingImage = false
                            }
                        }
                    }
                } else {
                    await MainActor.run {
                        withAnimation {
                            self?.isGeneratingImage = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        self?.isGeneratingImage = false
                    }
                }
                print("[AINotification] 图片生成失败: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func startModelGeneration() {
        stopAutoDismiss()
        isGeneratingModel = true

        Task { [weak self] in
            do {
                let prompt = self?.aiAnswer ?? "ai feedback model"
                let response = try await BackendAPI.shared.generate3DModel(prompt: prompt)

                guard response.success else {
                    await MainActor.run {
                        withAnimation {
                            self?.isGeneratingModel = false
                        }
                    }
                    return
                }

                await MainActor.run {
                    withAnimation {
                        self?.isGeneratingModel = false
                        self?.isModelReady = true
                        self?.modelURL = response.modelURL
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        self?.isGeneratingModel = false
                    }
                }
                print("[AINotification] 模型生成失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 主动反馈轮询

    private var feedbackPollingTask: Task<Void, Never>?

    @MainActor
    func startFeedbackPolling(interval: TimeInterval = 3.0) {
        feedbackPollingTask?.cancel()
        feedbackPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.pollLatestFeedback()
            }
        }
    }

    @MainActor
    func stopFeedbackPolling() {
        feedbackPollingTask?.cancel()
        feedbackPollingTask = nil
    }

    private func pollLatestFeedback() async {
        do {
            let response = try await BackendAPI.shared.fetchLatestFeedback()
            guard response.hasFeedback, let content = response.content else { return }
            await MainActor.run {
                self.showFeedback(content: content, scores: response.scores, totalScore: response.totalScore)
            }
        } catch {
            // 静默失败，继续下一轮轮询
        }
    }

    @MainActor
    private func showFeedback(content: String, scores: [String: Int]?, totalScore: Double?) {
        cancelAutoDismiss()
        currentNotificationID = UUID()

        // 将反馈内容作为消息展示
        withAnimation(.spring()) {
            message = content
            isShowing = true
        }

        scheduleAutoDismiss(for: currentNotificationID)
    }
}
