import SwiftUI
import RealityKit
import RealityKitContent

struct OverallEditView: View {
    enum ViewState {
        case edit
        case generatingImage
        case imageResult
        case modelPreview
    }

    var onDismiss: () -> Void

    @Environment(AppModel.self) private var appModel

    @State private var currentState: ViewState = .edit

    var body: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 20) {
            // 顶部导航
            HStack {
                Button(action: {
                    withAnimation {
                        if currentState == .edit {
                            onDismiss()
                        } else if currentState == .imageResult {
                            currentState = .edit
                        } else {
                            currentState = .imageResult
                        }
                    }
                }) {
                    Label(currentState == .edit ? "Cancel" : "Back", systemImage: currentState == .edit ? "xmark" : "chevron.left")
                }

                Spacer()

                Text("Overall Generation")
                    .font(.headline)

                Spacer()

                Button(action: onDismiss) {
                    Text("Done")
                }
                .disabled(currentState != .modelPreview || !appModel.overallDraft.isModelReady)
            }
            .padding(.horizontal)

            ZStack {
                switch currentState {
                case .edit:
                    EditContentPage
                case .generatingImage:
                    GeneratingImagePage
                case .imageResult:
                    ImageResultPage
                case .modelPreview:
                    ModelPreviewPage
                }
            }
        }
        .padding()
        .task {
            async let prompt = fetchPrompt()
            async let pending = fetchPendingPoints()
            async let components = appModel.overallFetchComponentImages()
            await (prompt, pending, components)
        }
    }

    private func fetchPrompt() async {
        do {
            let response = try await BackendAPI.shared.generateOverallPrompt()
            appModel.overallDraft.aiPrompt = response.prompt
            appModel.overallDraft.promptText = response.prompt
        } catch {
            print("[OverallEditView] 获取提示词失败: \(error.localizedDescription)")
        }
    }

    private func fetchPendingPoints() async {
        await appModel.overallFetchPendingPoints()
    }

    // MARK: - Edit Page

    private var EditContentPage: some View {
        @Bindable var appModel = appModel
        return VStack(spacing: 20) {
            // AI 提示词输入区
            TextEditor(text: $appModel.overallDraft.promptText)
                .padding()
                .background(.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(height: 120)
                .padding(.horizontal)

            // 下方三栏：照片 | AI建议 | 部件图
            HStack(alignment: .top, spacing: 16) {
                // 左侧：拍摄的照片
                PhotoSection
                    .frame(width: 440, height: 340)

                // 中间：AI 建议 / 确定问题
                AISuggestionsSection
                    .frame(height: 340)

                // 右侧：部件图
                ComponentImagesSection
                    .frame(height: 340)
            }

            // 右下角按钮
            HStack {
                Spacer()
                Button(action: startOverallGeneration) {
                    Text("Generate Overall Image")
                        .fontWeight(.bold)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                }
                .padding()
            }
        }
    }

    // MARK: - Photo Section

    @ViewBuilder
    private var PhotoSection: some View {
        @Bindable var appModel = appModel

        if let image = appModel.overallDraft.mainImage {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(4 / 3, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Button(action: { appModel.overallDraft.mainImage = nil }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(4)
                }
                .padding(8)
                .buttonStyle(.plain)
            }
        } else {
            Button(action: { appModel.overallLoadFirstPhotoFromLibrary() }) {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48))
                    Text("Tap to load the first photo from library")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - AI Suggestions Section

    private var AISuggestionsSection: some View {
        @Bindable var appModel = appModel
        return VStack(spacing: 12) {
            if !appModel.overallDraft.pendingPoints.isEmpty {
                HStack {
                    Text("AI Suggestions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(appModel.overallDraft.pendingPoints) { point in
                            PendingPointCard(point: point, onConfirm: { await appModel.overallConfirmPendingPoint(id: point.id) })
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: 300)
    }

    // MARK: - Component Images Section

    private var ComponentImagesSection: some View {
        let components = appModel.overallDraft.backendComponentImages

        return ScrollView {
            VStack(spacing: 12) {
                if components.isEmpty {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(0.2))
                            .frame(width: 200, height: 140)
                    }
                } else {
                    ForEach(components.indices, id: \.self) { index in
                        let comp = components[index]
                        VStack(spacing: 4) {
                            if let image = comp.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(width: 200, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.black.opacity(0.2))
                                    .frame(width: 200, height: 140)
                                    .overlay(ProgressView().scaleEffect(0.5))
                            }
                            Text(comp.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(4)
        }
        .frame(width: 220)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Generating Image Page

    private var GeneratingImagePage: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(2.0)
            Text("Generating overall image from AI suggestions...")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Image Result Page

    private var ImageResultPage: some View {
        @Bindable var appModel = appModel

        return VStack(spacing: 30) {
            TextField("Prompt...", text: $appModel.overallDraft.resultPromptText)
                .padding()
                .background(.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 60)

            if let image = appModel.overallDraft.generatedOverallImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.black.opacity(0.1))
                    .frame(width: 600, height: 400)
                    .overlay(ProgressView())
            }

            HStack {
                Spacer()
                Button(action: startModelGeneration) {
                    Text("Generate 3D Model")
                        .fontWeight(.bold)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                }
                .padding()
            }
        }
    }

    // MARK: - Model Preview Page

    private var ModelPreviewPage: some View {
        @Bindable var appModel = appModel

        return VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirmed Prompt")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(appModel.overallDraft.resultPromptText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            if appModel.overallDraft.isGeneratingModel {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(2.0)
                    Text("Generating overall 3D model...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if let modelURL = appModel.overallDraft.modelURL {
                OverallModelPreview(modelURL: modelURL)
            } else {
                Text("Waiting for model...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }

            HStack(spacing: 20) {
                Button(action: {
                    startModelGeneration()
                }) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.bordered)
                .clipShape(Capsule())
                .disabled(appModel.overallDraft.isGeneratingModel)

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func startOverallGeneration() {
        let finalPrompt = appModel.overallDraft.promptText

        Task {
            // 先保存提示词到后端
            await appModel.overallSavePrompt(finalPrompt)

            // 切换到生成中状态
            withAnimation {
                currentState = .generatingImage
            }

            // 调用后端生成整体图片
            await appModel.overallGenerateImage()

            // 生成完成，切换到结果页
            Task { @MainActor in
                appModel.overallDraft.resultPromptText = finalPrompt
                if appModel.overallDraft.generatedOverallImage != nil {
                    withAnimation {
                        currentState = .imageResult
                    }
                }
            }
        }
    }

    private func startModelGeneration() {
        let finalPrompt = appModel.overallDraft.resultPromptText
        Task {
            await appModel.overallSavePrompt(finalPrompt)
            await appModel.overallStartModelGeneration()
        }

        withAnimation {
            currentState = .modelPreview
        }
    }
}

// MARK: - Pending Point Card

struct OverallModelPreview: View {
    let modelURL: String
    @State private var modelEntity: ModelEntity? = nil

    var body: some View {
        if let entity = modelEntity {
            RealityView { content in
                entity.position = [0, 0, 0]
                content.add(entity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            RealityView { content in
                // 占位符已隐藏，模型加载完成后才会显示
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .task {
                await loadModel(from: modelURL)
            }
        }
    }

    private func loadModel(from urlString: String) async {
        print("[OverallModelPreview] 收到加载请求: \(urlString)")
        // 对中文进行百分号编码，确保 URL(string:) 能正确解析
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            print("[OverallModelPreview] URL 无效: \(urlString)")
            return
        }
        do {
            // 先下载到本地，再用 file:// URL 加载
            let tempURL = try await downloadModel(from: url)
            let loadedEntity = try await ModelEntity.loadModel(contentsOf: tempURL)
            print("[OverallModelPreview] 模型加载成功")
            loadedEntity.setScale([0.1, 0.1, 0.1], relativeTo: nil)
            await MainActor.run {
                modelEntity = loadedEntity
            }
        } catch {
            print("[OverallModelPreview] 加载失败: \(error.localizedDescription)")
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
        print("[OverallModelPreview] 下载完成: \(tempURL.path), \(data.count) bytes")
        return tempURL
    }
}

// MARK: - Pending Point Card

struct PendingPointCard: View {
    let point: AppModel.PendingPoint
    var onConfirm: () async -> Void

    @State private var isExpanded: Bool = false
    @State private var isConfirming: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // 标题行：部件名 + 展开箭头 + 确认按钮
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(point.title)
                        .font(.body)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.3))
                )
            }
            .buttonStyle(.plain)

            // 展开内容：AI 建议
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(point.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    HStack {
                        Spacer()
                        Button(action: {
                            Task {
                                withAnimation { isConfirming = true }
                                await onConfirm()
                                withAnimation { isConfirming = false }
                            }
                        }) {
                            if isConfirming {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 60, height: 28)
                            } else {
                                Label(
                                    point.isConfirmed ? "Confirmed" : "Confirm",
                                    systemImage: point.isConfirmed ? "checkmark.circle.fill" : "checkmark.circle"
                                )
                                .foregroundColor(point.isConfirmed ? .green : .white)
                                .font(.caption)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(point.isConfirmed ? Color.green.opacity(0.2) : Color.white.opacity(0.15))
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isConfirming || point.isConfirmed)
                    }
                    .padding(.bottom, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.15))
                )
            }
        }
    }
}

#Preview {
    OverallEditView(onDismiss: {})
}
