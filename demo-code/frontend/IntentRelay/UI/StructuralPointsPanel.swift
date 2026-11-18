import SwiftUI

struct StructuralPointsPanel: View {
    @Bindable var viewModel: UIBoardViewModel
    var isShowing: Bool
    var onEditPoint: (String, UIBoardViewModel.StructuralEditTarget) -> Void

    var body: some View {
        if isShowing {
            VStack(spacing: 10) {
                // 功能块
                if hasFunctionItems {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Function")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        ForEach(functionItems, id: \.self) { item in
                            HStack {
                                Text(item.label)
                                    .font(.callout)
                                Spacer()
                                Button {
                                    onEditPoint(item.text, item.target)
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
                    .padding()
                    .frame(width: 320)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // 结构块
                if hasStructureItems {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Structure")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        ForEach(structureItems, id: \.self) { item in
                            HStack {
                                Text(item.label)
                                    .font(.callout)
                                Spacer()
                                Button {
                                    onEditPoint(item.text, item.target)
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
                    .padding()
                    .frame(width: 320)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private struct EditItem: Hashable {
        let label: String
        let text: String
        let target: UIBoardViewModel.StructuralEditTarget
    }

    private var hasFunctionItems: Bool {
        viewModel.parts.contains { !$0.functionDescriptions.isEmpty }
    }

    private var hasStructureItems: Bool {
        viewModel.parts.contains { !$0.structuralDescriptions.isEmpty }
    }

    private var functionItems: [EditItem] {
        viewModel.parts.enumerated().flatMap { partIndex, part in
            part.functionDescriptions.enumerated().map { itemIndex, text in
                EditItem(
                    label: "\(part.name)：\(text)",
                    text: text,
                    target: .function(partIndex: partIndex, itemIndex: itemIndex)
                )
            }
        }
    }

    private var structureItems: [EditItem] {
        viewModel.parts.enumerated().flatMap { partIndex, part in
            part.structuralDescriptions.enumerated().map { itemIndex, text in
                EditItem(
                    label: "\(part.name)：\(text)",
                    text: text,
                    target: .structure(partIndex: partIndex, itemIndex: itemIndex)
                )
            }
        }
    }
}
