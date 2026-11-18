import Foundation
import RealityKit
import RealityKitContent
import UIKit

class GlobalEntityManager: ObservableObject {
    static let shared = GlobalEntityManager()
    @Published var creationEntity = Entity()
}
