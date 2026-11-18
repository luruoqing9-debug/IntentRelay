import SwiftUI
import RealityKit
import RealityKitContent

struct AINotificationView: View {
    @Bindable var viewModel: AINotificationViewModel
    private let scrollBottomAnchorID = "AINotificationBottomAnchor"
    
    private var hasGeneratedContent: Bool {
        viewModel.isGeneratingImage || viewModel.generatedImage != nil || viewModel.isGeneratingModel || viewModel.isModelReady
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 通知主体（仅在没有 AI 回答时显示）
                        if viewModel.aiAnswer == nil, let message = viewModel.message {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("AI Assistant")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(message)
                                    .font(.body)
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // AI 回答（语音反馈结果）
                        if viewModel.isFetchingAnswer {
                            VStack(spacing: 8) {
                                ProgressView("Fetching AI response...")
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else if let answer = viewModel.aiAnswer {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AI Response")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(answer)
                                    .font(.body)
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        
                        // 生成结果（按消息分段展示）
                        if viewModel.isGeneratingImage || viewModel.generatedImage != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Image Generation")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if viewModel.isGeneratingImage {
                                    ProgressView("Generating image...")
                                        .padding(.vertical, 8)
                                } else if let image = viewModel.generatedImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        
                        if viewModel.isGeneratingModel || viewModel.isModelReady {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Model Generation")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if viewModel.isGeneratingModel {
                                    ProgressView("Generating model...")
                                        .padding(.vertical, 8)
                                } else if viewModel.isModelReady, let modelURL = viewModel.modelURL {
                                    NotificationModelPreview(modelURL: modelURL)
                                } else if viewModel.isModelReady {
                                    Text("Model Ready")
                                        .font(.caption)
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(scrollBottomAnchorID)
                    }
                    .padding(8)
                }
                .frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // 交互按钮行
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.startImageGeneration()
                        scrollToBottom(proxy: proxy)
                    }) {
                        Label("Image", systemImage: "photo.stack")
                            .font(.caption)
                    }
                    .disabled(viewModel.isGeneratingImage || viewModel.aiAnswer == nil)
                    
                    Button(action: {
                        viewModel.startModelGeneration()
                        scrollToBottom(proxy: proxy)
                    }) {
                        Label("Model", systemImage: "cube.transparent")
                            .font(.caption)
                    }
                    .disabled(viewModel.isGeneratingModel)
                    
                    Button(action: { viewModel.toggleEvaluation() }) {
                        Label("Feedback", systemImage: viewModel.isEvaluating ? "mic.fill" : "mic")
                            .font(.caption)
                            .foregroundColor(viewModel.isEvaluating ? .red : .primary)
                    }
                    .disabled(viewModel.isFetchingAnswer)
                    .symbolEffect(.bounce, value: viewModel.isEvaluating)
    
                    Button(action: { viewModel.dismiss() }) {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .font(.caption)
                    }
                }
                .padding()
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .frame(width: 500)
            .padding()
            .glassBackgroundEffect()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(scrollBottomAnchorID, anchor: .bottom)
            }
        }
    }
}

struct NotificationModelPreview: View {
    let modelURL: String
    @State private var modelEntity: ModelEntity? = nil

    var body: some View {
        if let entity = modelEntity {
            RealityView { content in
                entity.position = [0, 0, 0]
                content.add(entity)
            }
            .frame(maxWidth: 480)
            .frame(height: 120)
            .frame(depth: 0)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Text("Loading model...")
                .font(.caption)
            .task {
                await loadModel(from: modelURL)
            }
        }
    }

    private func loadModel(from urlString: String) async {
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            print("[NotificationModelPreview] URL 无效: \(urlString)")
            return
        }
        do {
            let tempURL = try await downloadModel(from: url)
            let loadedEntity = try await ModelEntity.loadModel(contentsOf: tempURL)
            print("[NotificationModelPreview] 模型加载成功")
            loadedEntity.setScale([0.1, 0.1, 0.1], relativeTo: nil)
            await MainActor.run {
                modelEntity = loadedEntity
            }
        } catch {
            print("[NotificationModelPreview] 加载失败: \(error.localizedDescription)")
        }
    }

    private func downloadModel(from url: URL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(url.lastPathComponent)
        try data.write(to: tempURL)
        print("[NotificationModelPreview] 下载完成: \(tempURL.path), \(data.count) bytes")
        return tempURL
    }
}
