import RealityKit
import SwiftUI
import ARKit

struct UIBoardComponent:Component{
    public init() {
        
    }
}

struct UIBoardSystem: System {
    init(scene: RealityKit.Scene) {
    }
    
    static let query = EntityQuery(where: .has(UIBoardComponent.self))

    func update(context: SceneUpdateContext) {
        for UIBoardEntity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let pos = ImmersiveView.worldTracking.getPosition(),
                  let dir = ImmersiveView.worldTracking.getDirection() else {
                // ARKit 未就绪，跳过本次位置更新
                continue
            }

            // 偏移到相机正前方 0.5 米位置
            let offset: Float = 0.5
            let frontPosition = SIMD3<Float>(
                pos[0] + dir[0] * offset,
                pos[1] + dir[1] * offset,
                pos[2] + dir[2] * offset
            )

            UIBoardEntity.setPosition(frontPosition, relativeTo: nil)

        }
    }
}
