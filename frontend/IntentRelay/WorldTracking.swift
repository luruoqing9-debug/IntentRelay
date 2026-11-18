import ARKit
import RealityKit
import QuartzCore

@Observable class WorldTracking {
    let session = ARKitSession()
    let worldTracking = WorldTrackingProvider()
    static let shared = WorldTracking()
    func runARSession() async {
        Task {

            do {
                try await session.run([worldTracking])
            } catch {
                print(error)
            }
            // print("ARKit Session 运行中")
        }
    }

    func getTransform() -> simd_float4x4? {
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
        else {
            // print("[WorldTracking] queryDeviceAnchor 返回 nil，ARKit 未就绪")
            return nil
        }

        let transform = deviceAnchor.originFromAnchorTransform
        return transform
    }

    func getDirection() -> [Float]?{
        guard let mtx = getTransform() else { return nil }
        return [
            -Float(mtx.columns.2.x),
            -Float(mtx.columns.2.y),
            -Float(mtx.columns.2.z)
        ]
    }

    // 获取设备目前的位置（相对于原点）
    func getPosition() -> [Float]?{
        guard let mtx = getTransform() else { return nil }
        return [
            Float(mtx.columns.3.x),
            Float(mtx.columns.3.y),
            Float(mtx.columns.3.z)
        ]
    }
}
