//
//  ImmersiveView.swift
//  IntentRelay
//
//  Created by 蒋招衢 on 2026/4/18.
//

import SwiftUI
import RealityKit
import RealityKitContent
import UIKit

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel
    static let worldTracking = WorldTracking.shared
    @ObservedObject var entityManager = GlobalEntityManager.shared

    var body: some View {
        RealityView { content, attachments in
            entityManager.creationEntity = Entity()
            entityManager.creationEntity.name = "UserCreation"
            content.add(entityManager.creationEntity)

            // 创建头部锚点，面板将跟随头部
            let headAnchor = AnchorEntity(.head)
            headAnchor.name = "UIBoardHeadAnchor"
            content.add(headAnchor)

            // 初始添加已存在的模型
            for (index, model) in appModel.addedModels.enumerated() {
                addModelToSceneSync(model, at: index, content: content)
            }
        }
        update: { content, attachments in
            // 等待 attachment 就绪后添加到 headAnchor
            guard let headAnchor = content.entities.first(where: { $0.name == "UIBoardHeadAnchor" }) else {
                return
            }

            if headAnchor.findEntity(named: "UIBoardView") == nil {
                if let uiBoard = attachments.entity(for: "UIBoardView") {
                    uiBoard.name = "UIBoardView"
                    uiBoard.position = [0, -0.05, -0.5]  // 相对头部的偏移：正前方 0.5m，略下方
                    headAnchor.addChild(uiBoard)
                    print("[ImmersiveView] UIBoardView attached to headAnchor")
                }
            }

            // 响应模型库添加操作
            for (index, model) in appModel.addedModels.enumerated() {
                let entityName = "added_model_\(index)"
                if entityManager.creationEntity.findEntity(named: entityName) == nil {
                    addModelToSceneAsync(model, at: index, content: content)
                }
            }
        }
        attachments:{
            Attachment(id: "UIBoardView") {
                UIBoardView()
            }
        }
        .task{
            await ImmersiveView.worldTracking.runARSession()
        }
        .onAppear {
            print("[ImmersiveView] onAppear")

            // 接线截屏回调（语音说"截屏"时触发）
            SpeechManager.shared.screenshotCallback = { [appModel] in
                let screenshot = ImmersiveView.captureScreenImage()
                appModel.lastScreenshot = screenshot
                print("[ImmersiveView] 截屏已保存: \(screenshot.size)")

                // 显示"已截屏"提示
                withAnimation(.spring()) {
                    appModel.isShowingScreenshotTip = true
                }
                Task { @MainActor in
                    try await Task.sleep(for: .seconds(2))
                    withAnimation(.spring()) {
                        appModel.isShowingScreenshotTip = false
                    }
                }
            }
        }
        .onDisappear {
            print("[ImmersiveView] onDisappear")
        }
        .BasicGesture()
    }

    private func addModelToSceneSync(_ model: AppModel.GeneratedModel, at index: Int, content: RealityViewContent) {
        let placeholder = ModelEntity(
            mesh: .generateSphere(radius: 0.1),
            materials: [SimpleMaterial(color: .clear, isMetallic: false)]
        )
        placeholder.isEnabled = false
        setupModelInScene(placeholder, model: model, at: index, content: content)

        // 后台异步加载真实模型
        if let modelURL = model.modelURL,
           let encoded = modelURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            Task {
                do {
                    let tempURL = try await downloadModel(from: url)
                    let entity = try await ModelEntity.loadModel(contentsOf: tempURL)
                    entity.setScale([0.1, 0.1, 0.1], relativeTo: nil)
                    await MainActor.run {
                        let entityName = "added_model_\(index)"
                        if let oldEntity = entityManager.creationEntity.findEntity(named: entityName) {
                            oldEntity.removeFromParent()
                        }
                        setupModelInScene(entity, model: model, at: index, content: content)
                    }
                } catch {
                    print("[ImmersiveView] 加载模型 \(model.name) 失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private func addModelToSceneAsync(_ model: AppModel.GeneratedModel, at index: Int, content: RealityViewContent) {
        let placeholder = ModelEntity(
            mesh: .generateSphere(radius: 0.1),
            materials: [SimpleMaterial(color: .clear, isMetallic: false)]
        )
        placeholder.isEnabled = false
        setupModelInScene(placeholder, model: model, at: index, content: content)

        if let modelURL = model.modelURL,
           let encoded = modelURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            Task {
                do {
                    let tempURL = try await downloadModel(from: url)
                    let entity = try await ModelEntity.loadModel(contentsOf: tempURL)
                    entity.setScale([0.1, 0.1, 0.1], relativeTo: nil)
                    await MainActor.run {
                        let entityName = "added_model_\(index)"
                        if let oldEntity = entityManager.creationEntity.findEntity(named: entityName) {
                            oldEntity.removeFromParent()
                        }
                        setupModelInScene(entity, model: model, at: index, content: content)
                    }
                } catch {
                    print("[ImmersiveView] 加载模型 \(model.name) 失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private func setupModelInScene(_ entity: ModelEntity, model: AppModel.GeneratedModel, at index: Int, content: RealityViewContent) {
        entity.name = "added_model_\(index)"
        guard let position = ImmersiveView.worldTracking.getPosition(),
              let offset = ImmersiveView.worldTracking.getDirection() else {
            // ARKit 未就绪，使用默认位置
            entity.position = [0, 0.5, -2]
            entity.generateCollisionShapes(recursive: true)
            entity.components.set(InputTargetComponent(allowedInputTypes: .all))
            entity.components.set(TransformComponent())
            entity.components.set(HoverEffectComponent())
            entityManager.creationEntity.addChild(entity)
            return
        }
        entity.position = [position[0], 0.5, position[2]] + [offset[0], 0, offset[2]] * 2
        entity.generateCollisionShapes(recursive: true)
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.components.set(TransformComponent())
        entity.components.set(HoverEffectComponent())
        entity.components[TransformComponent.self]?.position = entity.position
        entity.components[TransformComponent.self]?.scale = entity.scale.x
        entity.components[TransformComponent.self]?.rotation = entity.orientation
        entityManager.creationEntity.addChild(entity)
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
        return tempURL
    }

    // 截屏：通过窗口渲染捕获当前画面
    static func captureScreenImage() -> UIImage {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIImage()
        }
        let size = window.bounds.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
