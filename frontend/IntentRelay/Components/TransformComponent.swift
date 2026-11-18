import RealityKit
import SwiftUI

struct TransformComponent:Component{
    var uniqueID: String = UUID().uuidString  // 唯一标识符
    var position: SIMD3<Float> = .zero
    var rotation: simd_quatf = simd_quaternion(0, 0, 0, 1)
    var scale: Float = 1
    var size: SIMD3<Float> = .one
    
    public init() {
                
    }
    

}
