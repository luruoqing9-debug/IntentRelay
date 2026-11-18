import Foundation

class BroadcastManager:ObservableObject{
    static let shared = BroadcastManager()
    @Published var isAddingUI:Bool = false
    @Published var isHidingUI:Bool = false
}
