import SwiftUI

struct PendingQuestionsPanel: View {
    @Bindable var viewModel: UIBoardViewModel
    var isShowing: Bool
    var onEditQuestion: (String, PendingEditTarget) -> Void

    enum PendingEditTarget: Hashable {
        case global(Int)
        case uncertain(partIndex: Int, itemIndex: Int)
    }

    var body: some View {
        if isShowing {
            VStack(alignment: .leading, spacing: 6) {
                // 部件的不确定项
                ForEach(uncertainItems, id: \.self) { item in
                    HStack {
                        Text(item.label)
                            .font(.callout)
                        Spacer()
                        Button {
                            onEditQuestion(item.content, item.target)
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // 通用问题
                if !viewModel.pendingQuestions.isEmpty {
                    ForEach(Array(viewModel.pendingQuestions.enumerated()), id: \.offset) { index, text in
                        HStack {
                            Text(text)
                                .font(.callout)
                            Spacer()
                            Button {
                                onEditQuestion(text, .global(index))
                            } label: {
                                Image(systemName: "pencil")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
            .frame(width: 320, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private struct PendingItem: Hashable {
        let label: String
        let content: String
        let target: PendingEditTarget
    }

    private var uncertainItems: [PendingItem] {
        viewModel.parts.enumerated().flatMap { partIndex, part in
            part.uncertainDescriptions.enumerated().map { itemIndex, item in
                PendingItem(
                    label: "\(part.name)：\(item.content)",
                    content: item.content,
                    target: .uncertain(partIndex: partIndex, itemIndex: itemIndex)
                )
            }
        }
    }
}
