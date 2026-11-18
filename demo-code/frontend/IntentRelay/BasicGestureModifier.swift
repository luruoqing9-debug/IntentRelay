//
//  BasicGestureModifier.swift
//  SIMR
//
//  Created by 蒋招衢 on 2025/4/21.
//

import SwiftUI
import RealityKit

extension View {
    func BasicGesture(

    ) -> some View {
        self.modifier(
            BasicGestureModifier(

            )
        )
    }
}

private struct BasicGestureModifier: ViewModifier {

    @Environment(AppModel.self) var appModel
    @State var circularIndicator: ModelEntity?
    @State private var isShowIndicator = false
    @State private var distanceToGround:Float?
    @ObservedObject var entityManager = GlobalEntityManager.shared
    
    let modelPredicate = QueryPredicate<Any>.has(TransformComponent.self)
    let previewThreshold:Float = 0.2
    let stickToGroundThreshold:Float = 0.1
    
    func body(content: Content) -> some View {
        content
        //位移手势(对象)
        .gesture(
            DragGesture()
                .targetedToEntity(where: modelPredicate)
                .onChanged{ value in
                    let initPosition = value.entity.components[TransformComponent.self]!.position
                    value.entity.position = initPosition + value.convert(value.translation3D, from: .local, to: entityManager.creationEntity)
                }
                .onEnded { value in
                    value.entity.components[TransformComponent.self]?.position = value.entity.position
                }
        )
        //旋转手势
        .gesture(
            RotateGesture3D()
                .targetedToEntity(where: modelPredicate)
                .onChanged{ value in
                    value.entity.transform.rotation = value.convert(value.gestureValue.rotation, from: .local, to: entityManager.creationEntity) * value.entity.components[TransformComponent.self]!.rotation
                }
                .onEnded { value in
                    value.entity.components[TransformComponent.self]?.rotation = value.entity.transform.rotation
                }
        )
        //缩放手势
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToEntity(where: modelPredicate)
                .onChanged { value in
                    let scaleFactor = Float(value.magnification)
                    let scaleBase = value.entity.components[TransformComponent.self]!.scale
                    value.entity.setScale([scaleBase * scaleFactor,scaleBase * scaleFactor,scaleBase * scaleFactor], relativeTo: entityManager.creationEntity)
                }
                .onEnded { value in
                    value.entity.components[TransformComponent.self]?.scale *= Float(value.magnification)
                }
        )
        //双击删除模型
        .gesture(
            TapGesture(count: 2)
                .targetedToEntity(where: modelPredicate)
                .onEnded { value in
                    let entityName = value.entity.name
                    // 从名称中解析 index
                    if entityName.hasPrefix("added_model_"),
                       let deletedIndex = Int(String(entityName.dropFirst("added_model_".count))) {
                        value.entity.removeFromParent()
                        appModel.addedModels.remove(at: deletedIndex)
                        // 重新索引：所有 index > deletedIndex 的实体名 -1
                        for child in entityManager.creationEntity.children {
                            if child.name.hasPrefix("added_model_"),
                               let oldIndex = Int(String(child.name.dropFirst("added_model_".count))),
                               oldIndex > deletedIndex {
                                child.name = "added_model_\(oldIndex - 1)"
                            }
                        }
                        print("[BasicGesture] 已删除模型: \(entityName)")
                    }
                }
        )
    }
}
