import SwiftUI
import Observation

@Observable
class UIBoardViewModel {
    struct Part: Identifiable, Hashable {
        var id = UUID()
        var name: String
        var functionDescriptions: [String] = []
        var structuralDescriptions: [String] = []
        var appearanceDescriptions: [String] = []
        var uncertainDescriptions: [UncertainItem] = []

        struct UncertainItem: Identifiable, Hashable {
            var id = UUID()
            var content: String
            var descType: String // 外形/功能/结构
        }
    }
    enum StructuralEditTarget: Hashable {
        case function(partIndex: Int, itemIndex: Int)
        case structure(partIndex: Int, itemIndex: Int)
        case appearance(partIndex: Int, itemIndex: Int)
        case uncertain(partIndex: Int, itemIndex: Int)
    }

    var parts: [Part] = []
    var pendingQuestions: [String] = []

    // UI 状态
    var isShowingStructuralPoints = false
    var isShowingPendingQuestions = false
    var isShowingModelLibrary = false

    // 录音状态（由 SpeechManager 驱动）
    @MainActor var currentMode: Int {
        SpeechManager.shared.currentMode
    }

    @MainActor var isRecording: Bool {
        SpeechManager.shared.isUserRecording
    }

    // MARK: - 录音控制（麦克风按钮触发，仅 mico=1）

    @MainActor func toggleRecording() {
        SpeechManager.shared.toggleRecording()
    }

    // MARK: - 分贝检测（应用启动时调用，mode=0）

    @MainActor func startAutoMode() {
        SpeechManager.shared.switchMode(to: 0)
    }

    // MARK: - 定时轮询

    private var timerCancellable: Task<Void, Never>?

    func startPolling() {
        timerCancellable?.cancel()
        timerCancellable = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchComponentsInfo()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func fetchComponentsInfo() async {
        do {
            let response = try await BackendAPI.shared.fetchComponentsInfo()
            var newParts: [Part] = []
            var componentMap: [String: Int] = [:]

            for item in response.structureInfo {
                let (name, content) = parseItem(item)
                if name.isEmpty { continue }
                let index = getOrCreatePart(name: name, in: &newParts, map: &componentMap)
                newParts[index].structuralDescriptions.append(content)
            }

            for item in response.functionInfo {
                let (name, content) = parseItem(item)
                if name.isEmpty { continue }
                let index = getOrCreatePart(name: name, in: &newParts, map: &componentMap)
                newParts[index].functionDescriptions.append(content)
            }

            for item in response.uncertainInfo {
                let index = getOrCreatePart(name: item.target, in: &newParts, map: &componentMap)
                newParts[index].uncertainDescriptions.append(
                    Part.UncertainItem(content: item.content, descType: item.descType)
                )
            }

            parts = newParts
        } catch {
            print("[UIBoardViewModel] fetchComponentsInfo 失败: \(error.localizedDescription)")
        }
    }

    private func parseItem(_ item: String) -> (name: String, content: String) {
        if let range = item.range(of: "：") {
            let name = String(item[..<range.lowerBound])
            let content = String(item[range.upperBound...])
            return (name, content)
        }
        return ("", item)
    }

    private func getOrCreatePart(name: String, in parts: inout [Part], map: inout [String: Int]) -> Int {
        if let index = map[name] {
            return index
        }
        let index = parts.count
        parts.append(Part(name: name))
        map[name] = index
        return index
    }

    func updateStructuralPoint(target: StructuralEditTarget, with newValue: String) {
        switch target {
        case .function(let partIndex, let itemIndex):
            guard parts.indices.contains(partIndex) else { return }
            guard parts[partIndex].functionDescriptions.indices.contains(itemIndex) else { return }
            parts[partIndex].functionDescriptions[itemIndex] = newValue
        case .structure(let partIndex, let itemIndex):
            guard parts.indices.contains(partIndex) else { return }
            guard parts[partIndex].structuralDescriptions.indices.contains(itemIndex) else { return }
            parts[partIndex].structuralDescriptions[itemIndex] = newValue
        case .appearance(let partIndex, let itemIndex):
            guard parts.indices.contains(partIndex) else { return }
            guard parts[partIndex].appearanceDescriptions.indices.contains(itemIndex) else { return }
            parts[partIndex].appearanceDescriptions[itemIndex] = newValue
        case .uncertain(let partIndex, let itemIndex):
            guard parts.indices.contains(partIndex) else { return }
            guard parts[partIndex].uncertainDescriptions.indices.contains(itemIndex) else { return }
            parts[partIndex].uncertainDescriptions[itemIndex].content = newValue
        }
    }

    func updatePendingQuestion(at index: Int, with newValue: String) {
        guard index >= 0 && index < pendingQuestions.count else { return }
        pendingQuestions[index] = newValue
    }
}
