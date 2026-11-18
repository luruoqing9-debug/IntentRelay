import SwiftUI
import RealityKit
import RealityKitContent

struct ComponentGeneratorView: View {
    enum ViewState {
        case image
        case model
    }

    var onDismiss: () -> Void
    var onComplete: (UIImage?) -> Void

    @Environment(AppModel.self) private var appModel
    @State private var currentState: ViewState = .image
    @State private var isEditingPartName: Bool = false
    @State private var tempEditValue: String = ""
    @State private var isFetchingPrompt: Bool = false
    @State private var isSavingPrompt: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: onDismiss) {
                    Label("Cancel", systemImage: "xmark")
                }
                Spacer()
                Text("Component Generation")
                    .font(.headline)
                Spacer()
                Button(action: {
                    Task {
                        let selectedImg = await appModel.componentFinalize()
                        onComplete(selectedImg)
                        onDismiss()
                    }
                }) {
                    Text("Done")
                }
                .disabled(currentState != .model || !appModel.componentDraft.isModelReady)
            }

            Divider()

            ZStack {
                switch currentState {
                case .image:
                    ImagePhasePage
                case .model:
                    ModelPreviewPage
                }
            }
        }
        .padding()
        .sheet(isPresented: $isEditingPartName) {
            EditFieldView(title: "Edit Component Name", value: $tempEditValue) {
                Task {
                    isFetchingPrompt = true
                    await appModel.componentSavePartName(tempEditValue)
                    isFetchingPrompt = false
                    isEditingPartName = false
                }
            }
        }
    }

    // MARK: - Image Phase Page

    private var ImagePhasePage: some View {
        @Bindable var appModel = appModel
        return VStack(spacing: 20) {
            // 部件名称行
            HStack {
                Button {
                    tempEditValue = appModel.componentDraft.partName
                    isEditingPartName = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                Text(appModel.componentDraft.partName.isEmpty ? "Unnamed Component" : appModel.componentDraft.partName)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            // 提示词输入区（模仿整体生成）
            TextEditor(text: $appModel.componentDraft.promptText)
                .padding()
                .background(.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(height: 120)
                .padding(.horizontal)

            // 照片区域
            if appModel.componentDraft.isGeneratingImages {
                loadingSection
            } else if appModel.componentDraft.generatedImages.contains(where: { $0 != nil }) {
                generatedImagesSection
            } else {
                photoPickerSection
            }

            // 底部生成按钮（右下角）
            HStack {
                Spacer()
                if !appModel.componentDraft.generatedImages.contains(where: { $0 != nil }) {
                    Button(action: generateComponentImages) {
                        Text("Generate Component Images")
                            .fontWeight(.bold)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                    }
                    .padding()
                } else {
                    Button(action: completeImageSelection) {
                        Text("Generate 3D Model")
                            .fontWeight(.bold)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .disabled(appModel.componentDraft.selectedGeneratedIndex == nil)
                }
            }
        }
    }

    private var photoPickerSection: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Reference photo of the physical model")

            if let image = appModel.componentDraft.referenceImage {
                HStack {
                    Spacer()
                    VStack {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: 480, height: 270)
                                .aspectRatio(16/9, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 20))

                            Button(action: { appModel.componentDraft.referenceImage = nil }) {
                                Image(systemName: "trash.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(4)
                            }
                            .padding(8)
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
            } else {
                HStack {
                    Spacer()
                    Button(action: { appModel.componentLoadFirstPhotoFromLibrary() }) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.largeTitle)
                            Text("Tap to load the first photo from library")
                                .font(.caption)
                        }
                        .frame(width: 480, height: 270)
                        .background(.regularMaterial)
                    }
                    .buttonStyle(.plain)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .buttonBorderShape(.roundedRectangle(radius: 20))
                    Spacer()
                }
            }
        }
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Generating component images...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var generatedImagesSection: some View {
        VStack(alignment: .center, spacing: 20) {
            // 返回上一步按钮
            Button(action: {
                // 清空生成结果，回到参考图选择页
                appModel.componentDraft.isGeneratingImages = false
                appModel.componentDraft.generatedImages = [nil, nil, nil]
                appModel.componentDraft.selectedGeneratedIndex = nil
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Re-upload Reference Image")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { index in
                    generatedImageChip(at: index)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical)
    }

    private func generatedImageChip(at index: Int) -> some View {
        Button(action: { appModel.componentSelectGeneratedImage(at: index) }) {
            if let image = appModel.componentDraft.generatedImages[index] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(appModel.componentDraft.selectedGeneratedIndex == index ? Color.white : Color.clear, lineWidth: 6)
                    )
                    .shadow(radius: appModel.componentDraft.selectedGeneratedIndex == index ? 10 : 0)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .overlay(ProgressView())
            }
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: 20))
        .hoverEffect()
    }

    // MARK: - Model Preview Page

    @State private var previewModelEntity: ModelEntity? = nil

    private var ModelPreviewPage: some View {
        @Bindable var appModel = appModel
        return VStack(spacing: 16) {
            VStack(spacing: 20) {
                if appModel.componentDraft.isGeneratingModel {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(2.0)
                        Text("Generating 3D model from image...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let entity = previewModelEntity {
                    RealityView { content in
                        entity.position = [0, 0, 0]
                        content.add(entity)
                    }
                    .onDisappear {
                        previewModelEntity?.removeFromParent()
                        previewModelEntity = nil
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                } else {
                    Text("Waiting for model...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            }

            HStack(spacing: 20) {
                Button(action: {
                    previewModelEntity?.removeFromParent()
                    previewModelEntity = nil
                    completeImageSelection()
                }) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.bordered)
                .clipShape(Capsule())
                .disabled(appModel.componentDraft.isGeneratingModel)

                Spacer()
            }
            .padding()
        }
        .task {
            // 处理 view 出现时 URL 已存在的情况
            if let url = appModel.libraryModels.last?.modelURL, !url.isEmpty {
                print("[ComponentGeneratorView] .task 检测到 URL，加载: \(url)")
                await loadModel(from: url)
            }
        }
        .onChange(of: appModel.libraryModels.last?.modelURL) { _, newURL in
            guard let urlString = newURL, !urlString.isEmpty else { return }
            print("[ComponentGeneratorView] onChange 检测到 URL 变化: \(urlString)")
            Task {
                await loadModel(from: urlString)
            }
        }
    }

    private func loadModel(from urlString: String) async {
        print("[ComponentGeneratorView] 尝试加载模型: \(urlString)")
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            print("[ComponentGeneratorView] URL 无效: \(urlString)")
            return
        }
        do {
            let tempURL = try await downloadModel(from: url)
            let entity = try await ModelEntity.loadModel(contentsOf: tempURL)
            print("[ComponentGeneratorView] 模型加载成功")
            entity.setScale([0.1, 0.1, 0.1], relativeTo: nil)
            previewModelEntity = entity
        } catch {
            print("[ComponentGeneratorView] 模型加载失败: \(error)")
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
        print("[ComponentGeneratorView] 下载完成: \(tempURL.path), \(data.count) bytes")
        return tempURL
    }

    // MARK: - Actions

    private func generateComponentImages() {
        // 先保存提示词到后端
        isSavingPrompt = true
        let currentPrompt = appModel.componentDraft.promptText
        Task {
            await appModel.componentSavePrompt(currentPrompt)
            isSavingPrompt = false

            // 然后调用真实后端生成图片
            await appModel.componentGenerateImages()
        }
    }

    private func completeImageSelection() {
        guard let idx = appModel.componentDraft.selectedGeneratedIndex else { return }
        let partName = appModel.componentDraft.partName
        let selectedFilename = "\(partName)_\(idx).png"
        let finalPrompt = appModel.componentDraft.promptText
        let currentImages = appModel.componentDraft.generatedImages
        let currentDesc = appModel.componentDraft.descriptionText
        let currentRef = appModel.componentDraft.referenceImage
        let selectedImage = currentImages[idx]

        // 提前创建 draft 副本并设置生成状态，避免 view 出现时状态为 false
        appModel.componentDraft.isGeneratingModel = true
        appModel.componentDraft.isModelReady = false

        Task {
            // 1. 调用后端选择图片 → 保存到 processed_images/，同步到 3d_image/
            do {
                _ = try await BackendAPI.shared.selectComponentImage(
                    componentName: partName,
                    selectedFilename: selectedFilename
                )
                // 2. 保存最终提示词
                await appModel.componentSavePrompt(finalPrompt)
            } catch {
                print("[Component] select 失败: \(error.localizedDescription)")
                appModel.componentDraft.isGeneratingModel = false
                return
            }

            // 3. 保存 artifact 到 library
            let newModel = AppModel.GeneratedModel(name: partName, color: .systemBlue, modelURL: nil)
            appModel.libraryModels.append(newModel)
            let artifact = AppModel.ComponentArtifact(
                partName: partName,
                descriptionText: currentDesc,
                referenceImage: currentRef,
                generatedImages: currentImages,
                selectedImage: selectedImage,
                model: newModel
            )
            appModel.componentArtifacts.append(artifact)

            // 4. 进入 3D 模型视图（此时 isGeneratingModel 已为 true）
            withAnimation(.easeInOut) {
                currentState = .model
            }

            // 5. 调用后端真实 3D 生成
            await appModel.componentStartModelGeneration(prompt: finalPrompt, partName: partName)

            // 6. 生成完成后只重置图片和输入字段，保留模型状态
            appModel.componentDraft.isGeneratingImages = false
            appModel.componentDraft.generatedImages = [nil, nil, nil]
            appModel.componentDraft.selectedGeneratedIndex = nil
            appModel.componentDraft.referenceImage = nil
            appModel.componentDraft.descriptionText = ""
        }
    }

    private func createMockImage() -> UIImage {
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemPink]
        let color = colors.randomElement() ?? .systemBlue
        return UIImage(systemName: "cube.fill")?.withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
    }

    // MARK: - Edit Sheet

    struct EditFieldView: View {
        let title: String
        @Binding var value: String
        var onSave: () -> Void

        var body: some View {
            NavigationStack {
                VStack(spacing: 20) {
                    TextField(title, text: $value, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .padding()
                    Spacer()
                }
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave()
                        }
                    }
                }
            }
            .frame(width: 400, height: 300)
        }
    }
}

#Preview {
    ComponentGeneratorView(onDismiss: {}, onComplete: { _ in })
}
