//
//  AppModel.swift
//  IntentRelay
//
//  Created by 蒋招衢 on 2026/4/18.
//

import SwiftUI
import Photos

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    // 最新截屏（语音说"截屏"时捕获，替代相册第一张）
    var lastScreenshot: UIImage?
    @ObservationIgnored var isShowingScreenshotTip = false

    enum ViewState {
        case main
        case chat
        case overallEdit
        case componentEdit
    }
    var currentState: ViewState = .main

    // 已生成的 3D 模型
    struct GeneratedModel: Identifiable {
        let id = UUID()
        let name: String
        let color: UIColor
        let modelURL: String? // 3D 模型 URL (.usdz)
    }
    var libraryModels: [GeneratedModel] = []
    var addedModels: [GeneratedModel] = []

    // 后端模型列表（从 /models_list 获取）
    var backendModels: [ModelItem] = []
    var isLoadingModels = false

    /// 从后端获取模型列表
    func fetchModelsList() async {
        isLoadingModels = true
        do {
            let response = try await BackendAPI.shared.fetchModelsList()
            backendModels = response.models
            print("[AppModel] 获取到 \(backendModels.count) 个后端模型")
        } catch {
            print("[AppModel] 获取模型列表失败: \(error.localizedDescription)")
            backendModels = []
        }
        isLoadingModels = false
    }

    struct ComponentDraft {
        var partName: String = ""
        var descriptionText: String = ""
        var aiPrompt: String = ""
        var promptText: String = ""
        var referenceImage: UIImage? = nil

        var isGeneratingImages: Bool = false
        var generatedImages: [UIImage?] = [nil, nil, nil]
        var selectedGeneratedIndex: Int? = nil

        var isGeneratingModel: Bool = false
        var isModelReady: Bool = false
        var modelURL: String? = nil
    }

    struct ComponentArtifact: Identifiable {
        let id = UUID()
        var partName: String
        var descriptionText: String
        var referenceImage: UIImage?
        var generatedImages: [UIImage?]
        var selectedImage: UIImage?
        var model: GeneratedModel?
    }

    var componentDraft = ComponentDraft()
    var componentArtifacts: [ComponentArtifact] = []

    struct PendingPoint: Identifiable {
        let id = UUID()
        var title: String
        var detail: String
        var isConfirmed: Bool = false
        // API params for confirm_suggestion
        let target: String
        let type: String
        let content: String
        let suggestion: String
    }

    struct OverallDraft {
        var aiPrompt: String = ""
        var promptText: String = ""
        var mainImage: UIImage? = nil
        var pendingPoints: [PendingPoint] = []
        /// 从后端获取的已生成部件图
        var backendComponentImages: [ComponentInfo] = []

        var isGeneratingImage: Bool = false
        var generatedOverallImage: UIImage? = nil
        var resultPromptText: String = ""

        var isGeneratingModel: Bool = false
        var isModelReady: Bool = false
        var modelURL: String? = nil
    }

    var overallDraft = OverallDraft()

    func componentLoadFirstPhotoFromLibrary() {
        print("[AppModel] 开始从相册加载参考图")
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        print("[AppModel] 相册中找到 \(assets.count) 张图片")
        guard let asset = assets.firstObject else {
            print("[AppModel] 相册中没有找到图片")
            return
        }
        print("[AppModel] 获取到最新图片: \(asset)")

        // 使用 requestImageDataAndOrientation 替代 requestImage，避免降级图/高清图异步时序问题
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: nil) { [weak self] data, uti, orientation, info in
            print("[AppModel] requestImageDataAndOrientation 回调: data=\(data?.count ?? 0) bytes, uti=\(uti ?? "nil"), info=\(info ?? [:])")
            guard let self, let data = data, let image = UIImage(data: data) else {
                print("[AppModel] 无法从相册加载图片")
                return
            }
            Task { @MainActor in
                self.componentDraft.referenceImage = image
                print("[AppModel] 参考图加载成功: \(image.size)")
            }
        }
    }

    func componentSavePartName(_ name: String) async {
        componentDraft.partName = name
        // 从后端获取该部件的提示词
        if !name.isEmpty {
            do {
                let response = try await BackendAPI.shared.generateComponentPrompt(componentName: name)
                componentDraft.aiPrompt = response.prompt
                componentDraft.promptText = response.prompt
            } catch {
                print("[AppModel] 获取部件提示词失败: \(error.localizedDescription)")
                componentDraft.promptText = ""
            }
        } else {
            componentDraft.promptText = ""
        }
    }

    func componentGenerateImages() async {
        componentDraft.isGeneratingImages = true
        componentDraft.selectedGeneratedIndex = nil

        do {
            // 1. 上传参考图
            if let referenceImage = componentDraft.referenceImage {
                try await BackendAPI.shared.uploadReferenceImage(referenceImage, targetName: componentDraft.partName)
            }

            // 2. 调用 /generate_image，后端内部生成 3 张候选图
            let response = try await BackendAPI.shared.generateComponentImage(
                prompt: componentDraft.promptText,
                componentName: componentDraft.partName
            )

            guard response.success else {
                componentDraft.isGeneratingImages = false
                return
            }

            // 3. 并行下载 3 张候选图
            var fetchedImages: [UIImage?] = []
            for urlString in response.imagePaths {
                let fullURL = urlString.hasPrefix("http") ? urlString : "\(BackendAPI.shared.baseURL)\(urlString)"
                if let image = await BackendAPI.shared.downloadImage(from: fullURL) {
                    fetchedImages.append(image)
                } else {
                    fetchedImages.append(nil)
                }
            }

            // 补齐到 3 张
            while fetchedImages.count < 3 {
                fetchedImages.append(nil)
            }

            componentDraft.generatedImages = Array(fetchedImages.prefix(3))
        } catch {
            print("[AppModel] 部件候选图生成失败: \(error.localizedDescription)")
        }

        componentDraft.isGeneratingImages = false
    }

    /// 用户选择一张候选图，调用 /select_component_image 保存到 processed_images
    func componentSelectImage() async {
        guard let idx = componentDraft.selectedGeneratedIndex,
              (0..<componentDraft.generatedImages.count).contains(idx),
              let selectedImage = componentDraft.generatedImages[idx] else {
            return
        }

        let selectedFilename = "\(componentDraft.partName)_\(idx).png"
        do {
            _ = try await BackendAPI.shared.selectComponentImage(
                componentName: componentDraft.partName,
                selectedFilename: selectedFilename
            )
        } catch {
            print("[AppModel] 选择部件图失败: \(error.localizedDescription)")
        }
    }

    func componentSavePrompt(_ userPrompt: String) async {
        guard !componentDraft.partName.isEmpty else { return }
        do {
            let _ = try await BackendAPI.shared.updateMemoryFromPrompt(
                mode: 1,
                componentName: componentDraft.partName,
                aiPrompt: componentDraft.aiPrompt,
                userPrompt: userPrompt
            )
            // 更新本地存储的用户修改后的提示词
            componentDraft.promptText = userPrompt
        } catch {
            print("[AppModel] 保存部件提示词失败: \(error.localizedDescription)")
        }
    }

    func componentSelectGeneratedImage(at index: Int) {
        guard (0..<componentDraft.generatedImages.count).contains(index) else { return }
        componentDraft.selectedGeneratedIndex = index
    }

    func componentStartModelGeneration(prompt: String, partName: String) async {
        withAnimation(.easeInOut) {
            componentDraft.isGeneratingModel = true
            componentDraft.isModelReady = false
        }

        do {
            let response = try await BackendAPI.shared.generate3DModel(
                prompt: prompt,
                modelName: partName
            )

            guard response.success else {
                print("[AppModel] 3D 模型生成失败: 后端返回失败")
                withAnimation {
                    componentDraft.isGeneratingModel = false
                }
                return
            }

            let modelURL = response.modelURL
            print("[AppModel] 3D 模型生成成功: \(modelURL)")

            // 更新 libraryModels 中最新模型的 URL
            if let lastIdx = libraryModels.indices.last {
                libraryModels[lastIdx] = GeneratedModel(
                    name: libraryModels[lastIdx].name,
                    color: libraryModels[lastIdx].color,
                    modelURL: modelURL
                )
            }

            // 刷新后端模型列表，让模型库面板显示最新状态
            // 使用 do/catch 避免刷新失败时清空已有数据
            do {
                let response = try await BackendAPI.shared.fetchModelsList()
                backendModels = response.models
                print("[AppModel] 刷新模型列表: \(backendModels.count) 个模型")
            } catch {
                print("[AppModel] 刷新模型列表失败（不影响已生成模型）: \(error.localizedDescription)")
            }

            withAnimation {
                componentDraft.isGeneratingModel = false
                componentDraft.isModelReady = true
            }
        } catch {
            print("[AppModel] 3D 模型生成失败: \(error.localizedDescription)")
            withAnimation {
                componentDraft.isGeneratingModel = false
            }
        }
    }

    func componentFinalize() -> UIImage? {
        let selectedImage: UIImage? = {
            guard let idx = componentDraft.selectedGeneratedIndex else { return nil }
            guard componentDraft.generatedImages.indices.contains(idx) else { return nil }
            return componentDraft.generatedImages[idx]
        }()

        let newModel = GeneratedModel(name: componentDraft.partName, color: .systemBlue, modelURL: nil)
        libraryModels.append(newModel)

        let artifact = ComponentArtifact(
            partName: componentDraft.partName,
            descriptionText: componentDraft.descriptionText,
            referenceImage: componentDraft.referenceImage,
            generatedImages: componentDraft.generatedImages,
            selectedImage: selectedImage,
            model: newModel
        )
        componentArtifacts.append(artifact)

        componentDraft = ComponentDraft()
        return selectedImage
    }

    func overallLoadFirstPhotoFromLibrary() {
        print("[AppModel] 开始从相册加载主图")
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        print("[AppModel] 相册中找到 \(assets.count) 张图片")
        guard let asset = assets.firstObject else {
            print("[AppModel] 相册中没有找到图片")
            return
        }
        print("[AppModel] 获取到最新图片: \(asset)")

        // 使用 requestImageDataAndOrientation 替代 requestImage，避免降级图/高清图异步时序问题
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: nil) { [weak self] data, uti, orientation, info in
            print("[AppModel] requestImageDataAndOrientation 回调: data=\(data?.count ?? 0) bytes, uti=\(uti ?? "nil"), info=\(info ?? [:])")
            guard let self, let data = data, let image = UIImage(data: data) else {
                print("[AppModel] 无法从相册加载图片")
                return
            }
            Task { @MainActor in
                self.overallDraft.mainImage = image
                print("[AppModel] 主图加载成功: \(image.size)")
            }
        }
    }

    func overallConfirmPendingPoint(id: UUID) async {
        guard let index = overallDraft.pendingPoints.firstIndex(where: { $0.id == id }) else { return }
        let point = overallDraft.pendingPoints[index]
        guard !point.isConfirmed else { return }
        do {
            let response = try await BackendAPI.shared.confirmSuggestion(
                target: point.target,
                type: point.type,
                content: point.content,
                suggestion: point.suggestion
            )
            if response.success {
                withAnimation {
                    overallDraft.pendingPoints[index].isConfirmed = true
                    overallDraft.pendingPoints[index].detail = "Current: \(response.updatedContent)"
                }
                print("[AppModel] 确认成功: \(response.message)")
            }
        } catch {
            print("[AppModel] 确认失败: \(error.localizedDescription)")
        }
    }

    func overallFetchPendingPoints() async {
        do {
            let response = try await BackendAPI.shared.fetchUncertainSuggestions()
            overallDraft.pendingPoints = response.uncertainItems.map { item in
                PendingPoint(
                    title: "\(item.target) - \(item.type)",
                    detail: "Current: \(item.content)\n\nAI Suggestion: \(item.suggestion)",
                    target: item.target,
                    type: item.type,
                    content: item.content,
                    suggestion: item.suggestion
                )
            }
        } catch {
            print("[AppModel] 获取不确定建议失败: \(error.localizedDescription)")
            overallDraft.pendingPoints = []
        }
    }

    /// 从后端获取已生成的部件列表及图片
    func overallFetchComponentImages() async {
        do {
            let components = try await BackendAPI.shared.fetchComponentList()
            // 并行下载所有部件图
            var fetchedComponents = components
            await withTaskGroup(of: (Int, UIImage?).self) { group in
                for (index, comp) in fetchedComponents.enumerated() {
                    group.addTask {
                        let image = await BackendAPI.shared.downloadImage(from: comp.imageURL)
                        return (index, image)
                    }
                }
                for await (index, image) in group {
                    fetchedComponents[index].image = image
                }
            }
            overallDraft.backendComponentImages = fetchedComponents
            print("[AppModel] 获取到 \(fetchedComponents.count) 个后端部件图")
        } catch {
            print("[AppModel] 获取部件列表失败: \(error.localizedDescription)")
            overallDraft.backendComponentImages = []
        }
    }

    func overallSavePrompt(_ userPrompt: String) async {
        do {
            let _ = try await BackendAPI.shared.updateMemoryFromPrompt(
                mode: 2,
                componentName: "",
                aiPrompt: overallDraft.aiPrompt,
                userPrompt: userPrompt
            )
            overallDraft.resultPromptText = userPrompt
        } catch {
            print("[AppModel] 保存整体提示词失败: \(error.localizedDescription)")
        }
    }

    /// 调用后端 /generate_image (mode=2) 生成整体图片
    func overallGenerateImage() async {
        overallDraft.isGeneratingImage = true
        overallDraft.generatedOverallImage = nil

        do {
            // 1. 先上传参考图
            if let referenceImage = overallDraft.mainImage {
                try await BackendAPI.shared.uploadReferenceImage(referenceImage, targetName: "overall")
            }

            // 2. 调用 /generate_image，后端内部生成整体图
            let response = try await BackendAPI.shared.generateOverallImage(prompt: overallDraft.promptText)

            guard response.success, !response.imagePaths.isEmpty else {
                overallDraft.isGeneratingImage = false
                return
            }

            // 从返回的 URL 下载图片
            let imageURL = response.imagePaths[0]
            if let image = await BackendAPI.shared.downloadImage(from: imageURL) {
                overallDraft.generatedOverallImage = image
            }
        } catch {
            print("[AppModel] 整体图片生成失败: \(error.localizedDescription)")
        }

        overallDraft.isGeneratingImage = false
    }

    func overallStartModelGeneration() async {
        withAnimation {
            overallDraft.isGeneratingModel = true
            overallDraft.isModelReady = false
        }

        do {
            let response = try await BackendAPI.shared.generate3DModel(
                prompt: overallDraft.resultPromptText
            )

            guard response.success else {
                print("[AppModel] 整体 3D 模型生成失败: 后端返回失败")
                withAnimation {
                    overallDraft.isGeneratingModel = false
                }
                return
            }

            let modelURL = response.modelURL
            print("[AppModel] 整体 3D 模型生成成功: \(modelURL)")

            // 刷新后端模型列表，让模型库面板显示最新状态
            do {
                let response = try await BackendAPI.shared.fetchModelsList()
                backendModels = response.models
                print("[AppModel] 刷新模型列表: \(backendModels.count) 个模型")
            } catch {
                print("[AppModel] 刷新模型列表失败（不影响已生成模型）: \(error.localizedDescription)")
            }

            withAnimation {
                overallDraft.isGeneratingModel = false
                overallDraft.isModelReady = true
                overallDraft.modelURL = modelURL
            }
        } catch {
            print("[AppModel] 整体 3D 模型生成失败: \(error.localizedDescription)")
            withAnimation {
                overallDraft.isGeneratingModel = false
            }
        }
    }

    private func createMockImage() -> UIImage {
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemPink]
        let color = colors.randomElement() ?? .systemBlue
        return UIImage(systemName: "cube.fill")?.withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
    }
}
