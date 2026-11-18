import SwiftUI

struct AIChatView: View {
    @State private var messageText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading: Bool = false
    @State private var hasQuestions: Bool = false
    @State private var currentQuestion: QAQuestion?
    @State private var errorMessage: String?

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                Text("AI Assistant")
                    .font(.headline)
                Spacer()
                Button(action: onComplete) {
                    Text("Done")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // 聊天内容区
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        if isLoading {
                            ProgressView("AI is analyzing memory...")
                                .padding(.top, 40)
                        }

                        if messages.isEmpty && !isLoading && !hasQuestions {
                            VStack(spacing: 12) {
                                Text("Waiting for AI to analyze memory")
                                    .foregroundColor(.secondary)
                                Button("Start Memory QA") {
                                    Task { await startQARound() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        ForEach(messages) { message in
                            ChatBubble(message: message)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }

            // 错误提示
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            // 输入区：仅在有问题待回答时启用
            HStack(spacing: 12) {
                TextField("Type your answer...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .disabled(!hasQuestions || isLoading)
                    .onSubmit {
                        Task { await sendAnswer() }
                    }

                Button(action: {
                    Task { await sendAnswer() }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20))
                }
                .disabled(!hasQuestions || isLoading || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: {
                    Task { await skipAnswer() }
                }) {
                    Text("Skip")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!hasQuestions || isLoading)
            }
            .padding()
        }
        .task {
            await startQARound()
        }
    }

    // MARK: - Backend Interaction

    private func startQARound() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await BackendAPI.shared.startMemoryQA()
            isLoading = false

            if response.hasQuestions, let question = response.currentQuestion {
                hasQuestions = true
                currentQuestion = question

                let aiMessage = ChatMessage(text: question.question, isUser: false, metadata: question)
                withAnimation {
                    messages.append(aiMessage)
                }
            } else {
                hasQuestions = false
            }
        } catch {
            isLoading = false
            errorMessage = "Unable to start memory QA: \(error.localizedDescription)"
        }
    }

    private func skipAnswer() async {
        guard hasQuestions else { return }

        withAnimation {
            messages.append(ChatMessage(text: "Skipped this question", isUser: true))
        }
        isLoading = true

        do {
            let response = try await BackendAPI.shared.answerMemoryQA(answer: "SKIP")
            isLoading = false

            if let updateResult = response.updateResult, !updateResult.isEmpty {
                let resultMsg = ChatMessage(text: updateResult, isUser: false)
                withAnimation {
                    messages.append(resultMsg)
                }
            }

            if response.hasQuestions, let nextQuestion = response.currentQuestion {
                hasQuestions = true
                currentQuestion = nextQuestion

                let aiMsg = ChatMessage(text: nextQuestion.question, isUser: false, metadata: nextQuestion)
                withAnimation {
                    messages.append(aiMsg)
                }
            } else {
                hasQuestions = false
                currentQuestion = nil

                let endMsg = ChatMessage(text: "All questions processed", isUser: false)
                withAnimation {
                    messages.append(endMsg)
                }
            }
        } catch {
            isLoading = false
            errorMessage = "Skip failed: \(error.localizedDescription)"
        }
    }

    private func sendAnswer() async {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, hasQuestions else { return }

        let userMsg = ChatMessage(text: trimmed, isUser: true)
        withAnimation {
            messages.append(userMsg)
        }
        messageText = ""
        isLoading = true

        do {
            let response = try await BackendAPI.shared.answerMemoryQA(answer: trimmed)
            isLoading = false

            if let updateResult = response.updateResult, !updateResult.isEmpty {
                let resultMsg = ChatMessage(text: updateResult, isUser: false)
                withAnimation {
                    messages.append(resultMsg)
                }
            }

            if response.hasQuestions, let nextQuestion = response.currentQuestion {
                hasQuestions = true
                currentQuestion = nextQuestion

                let aiMsg = ChatMessage(text: nextQuestion.question, isUser: false, metadata: nextQuestion)
                withAnimation {
                    messages.append(aiMsg)
                }
            } else {
                hasQuestions = false
                currentQuestion = nil

                let endMsg = ChatMessage(text: "All questions processed", isUser: false)
                withAnimation {
                    messages.append(endMsg)
                }
            }
        } catch {
            isLoading = false
            errorMessage = "Failed to send answer: \(error.localizedDescription)"
        }
    }
}

// MARK: - Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let metadata: QAQuestion?

    init(text: String, isUser: Bool, metadata: QAQuestion? = nil) {
        self.text = text
        self.isUser = isUser
        self.metadata = metadata
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            Text(message.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(message.isUser ? Color.white : Color.gray.opacity(0.2))
                .foregroundColor(message.isUser ? .black.opacity(0.8) : .primary)
                .clipShape(ChatBubbleShape(isUser: message.isUser))

            if !message.isUser { Spacer() }
        }
    }
}

struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect,
                               byRoundingCorners: [.topLeft, .topRight, isUser ? .bottomLeft : .bottomRight],
                               cornerRadii: CGSize(width: 16, height: 16))
        return Path(path.cgPath)
    }
}

#Preview {
    AIChatView(onComplete: {})
}
