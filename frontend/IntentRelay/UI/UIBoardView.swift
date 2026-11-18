import SwiftUI
import AVFoundation
import RealityKit

struct UIBoardView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel = UIBoardViewModel()
    @State private var notificationViewModel = AINotificationViewModel()
    @StateObject private var speechManager = SpeechManager.shared
    
    // 编辑弹窗相关的状态
    @State private var isShowingEditSheet = false
    @State private var editingText = ""
    @State private var editingTarget: EditingTarget? = nil

    private enum EditingTarget: Hashable {
        case structural(UIBoardViewModel.StructuralEditTarget)
        case pendingQuestion(PendingQuestionsPanel.PendingEditTarget)
    }
    
    var body: some View {
        ZStack {
            // 背景内容层：左下角通知
            VStack {
                Spacer()
                HStack {
                    if notificationViewModel.isShowing {
                        AINotificationView(viewModel: notificationViewModel)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(.leading, 60)
                .padding(.bottom, 60)
            }

            // 背景内容层：右下角录音
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Spacer()

                    // 3D 模型库按钮
                    Button {
                        withAnimation(.spring()) {
                            viewModel.isShowingModelLibrary.toggle()
                        }
                    } label: {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.largeTitle)
                            .padding()
                            .glassBackgroundEffect()
                    }
                    .buttonStyle(.plain)
                    
                    if !notificationViewModel.isEvaluating {
                        MainMicrophoneButton(
                            speechManager: speechManager,
                            isDisabled: false
                        )
                    }
                }
                .padding(.trailing, 80)
                .padding(.bottom, 60)
            }

            // 3D 模型库面板
            if viewModel.isShowingModelLibrary {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ModelLibraryPanel(viewModel: viewModel, appModel: appModel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 100)
                            .padding(.trailing, 80)
                    }
                }
            }

            // UI 控制层：顶部面板开关与数据面板
            VStack {
                TopControlBar(viewModel: viewModel)
                    .padding(.leading, 50)
                    .padding(.trailing, 80)
                    .padding(.top, -12)

                DataPanelsRow(
                    viewModel: viewModel,
                    onEditStructural: { text, target in
                        startEditingStructural(text: text, target: target)
                    },
                    onEditQuestion: { text, target in
                        startEditingPendingQuestion(text: text, target: target)
                    }
                )
                .padding(.leading, 60)
                .padding(.trailing, 100)
                
                Spacer()
            }
            
            // 背景内容层：中下方截屏提示
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("Screenshot Captured")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                    Spacer()
                }
                .padding(.bottom, 40)
            }
            .opacity(appModel.isShowingScreenshotTip ? 1 : 0)

            // 自定义编辑层
            if isShowingEditSheet {
                UIBoardEditView(
                    text: $editingText,
                    isPresented: $isShowingEditSheet,
                    onSave: saveEdit
                )
            }
        }
        .frame(width: 1024, height: 576)
        .onAppear {
            viewModel.startPolling()
            viewModel.startAutoMode()

            // mico=1: AI 回答 → 通知面板
            SpeechManager.shared.qaCallback = { [notificationViewModel] answer in
                withAnimation(.spring()) {
                    notificationViewModel.message = answer
                    notificationViewModel.aiAnswer = answer
                    notificationViewModel.isShowing = true
                    notificationViewModel.stopAutoDismiss()
                }
            }

            // 主动反馈轮询（每 3 秒）
            notificationViewModel.startFeedbackPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
            notificationViewModel.stopFeedbackPolling()
        }
    }
    
    // MARK: - Helper Views
    
    struct MainMicrophoneButton: View {
        @ObservedObject var speechManager: SpeechManager
        var isDisabled: Bool

        var body: some View {
            Button {
                speechManager.toggleRecording()
            } label: {
                mainButtonIcon
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }

        private var mainButtonIcon: some View {
            let icon: String
            let color: Color
            switch speechManager.currentMode {
            case 0:
                icon = "mic"
                color = .primary
            case 1:
                icon = speechManager.isUserRecording ? "stop.circle.fill" : "mic.circle.fill"
                color = speechManager.isUserRecording ? .red : .accentColor
            case 2:
                icon = "mic.slash.fill"
                color = .orange
            default:
                icon = "mic"
                color = .primary
            }
            return Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(color)
                .padding()
                .glassBackgroundEffect()
                .symbolEffect(.bounce, value: speechManager.isUserRecording)
        }
    }
    
    struct TopControlBar: View {
        @Bindable var viewModel: UIBoardViewModel
        
        var body: some View {
            HStack {
                Button {
                    withAnimation(.spring()) {
                        viewModel.isShowingStructuralPoints.toggle()
                    }
                } label: {
                    Label(viewModel.isShowingStructuralPoints ? "Hide Structure Points" : "Show Structure Points", systemImage: viewModel.isShowingStructuralPoints ? "eye.slash" : "eye")
                }
                .padding()
                
                Spacer()
                
                Button {
                    withAnimation(.spring()) {
                        viewModel.isShowingPendingQuestions.toggle()
                    }
                } label: {
                    Label(viewModel.isShowingPendingQuestions ? "Hide Pending Questions" : "Show Pending Questions", systemImage: viewModel.isShowingPendingQuestions ? "eye.slash" : "eye")
                }
                .padding()
            }
        }
    }
    
    struct DataPanelsRow: View {
        var viewModel: UIBoardViewModel
        var onEditStructural: (String, UIBoardViewModel.StructuralEditTarget) -> Void
        var onEditQuestion: (String, PendingQuestionsPanel.PendingEditTarget) -> Void
        
        var body: some View {
            HStack(alignment: .top) {
                StructuralPointsPanel(
                    viewModel: viewModel,
                    isShowing: viewModel.isShowingStructuralPoints,
                    onEditPoint: onEditStructural
                )

                Spacer()

                PendingQuestionsPanel(
                    viewModel: viewModel,
                    isShowing: viewModel.isShowingPendingQuestions,
                    onEditQuestion: onEditQuestion
                )
            }
        }
    }
    
    // MARK: - Editing Logic
    
    private func startEditingStructural(text: String, target: UIBoardViewModel.StructuralEditTarget) {
        editingText = text
        editingTarget = .structural(target)
        withAnimation(.spring(duration: 0.3)) {
            isShowingEditSheet = true
        }
    }

    private func startEditingPendingQuestion(text: String, target: PendingQuestionsPanel.PendingEditTarget) {
        editingText = text
        editingTarget = .pendingQuestion(target)
        withAnimation(.spring(duration: 0.3)) {
            isShowingEditSheet = true
        }
    }
    
    private func saveEdit() {
        guard let editingTarget else { return }
        Task {
            do {
                switch editingTarget {
                case .structural(let target):
                    let (targetName, descType, oldContent) = resolveStructuralTarget(target)
                    if targetName.isEmpty { return }
                    try await BackendAPI.shared.updateDescription(
                        targetName: targetName,
                        descType: descType,
                        oldContent: oldContent,
                        newContent: editingText
                    )
                    viewModel.updateStructuralPoint(target: target, with: editingText)

                case .pendingQuestion(let target):
                    switch target {
                    case .global(let index):
                        viewModel.updatePendingQuestion(at: index, with: editingText)
                    case .uncertain(let partIndex, let itemIndex):
                        let uncertainItem = viewModel.parts[partIndex].uncertainDescriptions[itemIndex]
                        try await BackendAPI.shared.updateDescription(
                            targetName: viewModel.parts[partIndex].name,
                            descType: uncertainItem.descType,
                            oldContent: uncertainItem.content,
                            newContent: editingText
                        )
                        viewModel.updateStructuralPoint(target: .uncertain(partIndex: partIndex, itemIndex: itemIndex), with: editingText)
                    }
                }
            } catch {
                print("[UIBoardView] saveEdit 失败: \(error.localizedDescription)")
            }
            withAnimation(.spring(duration: 0.3)) {
                isShowingEditSheet = false
            }
        }
    }

    private func resolveStructuralTarget(_ target: UIBoardViewModel.StructuralEditTarget) -> (targetName: String, descType: String, oldContent: String) {
        switch target {
        case .function(let partIndex, let itemIndex):
            guard viewModel.parts.indices.contains(partIndex) else { return ("", "", "") }
            guard viewModel.parts[partIndex].functionDescriptions.indices.contains(itemIndex) else { return ("", "", "") }
            return (viewModel.parts[partIndex].name, "功能", viewModel.parts[partIndex].functionDescriptions[itemIndex])
        case .structure(let partIndex, let itemIndex):
            guard viewModel.parts.indices.contains(partIndex) else { return ("", "", "") }
            guard viewModel.parts[partIndex].structuralDescriptions.indices.contains(itemIndex) else { return ("", "", "") }
            return (viewModel.parts[partIndex].name, "结构", viewModel.parts[partIndex].structuralDescriptions[itemIndex])
        case .appearance(let partIndex, let itemIndex):
            guard viewModel.parts.indices.contains(partIndex) else { return ("", "", "") }
            guard viewModel.parts[partIndex].appearanceDescriptions.indices.contains(itemIndex) else { return ("", "", "") }
            return (viewModel.parts[partIndex].name, "外形", viewModel.parts[partIndex].appearanceDescriptions[itemIndex])
        case .uncertain:
            return ("", "", "")
        }
    }
}

#Preview {
    UIBoardView()
}
