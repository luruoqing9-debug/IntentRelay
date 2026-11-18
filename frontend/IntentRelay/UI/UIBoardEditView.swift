import SwiftUI

struct UIBoardEditView: View {
    @Binding var text: String
    @Binding var isPresented: Bool
    var onSave: () -> Void
    
    var body: some View {
        ZStack {
            // 编辑卡片
            VStack(spacing: 12) {
                HStack {
                    Text("Edit")
                        .font(.headline)
                    Spacer()
                }
                
                TextField("Content", text: $text, axis: .vertical)
                    .font(.body)
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .lineLimit(1...4)
                
                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel") {
                        withAnimation(.spring(duration: 0.3)) {
                            isPresented = false
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    
                    Button("Save") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(16)
            .frame(width: 300)
            .glassBackgroundEffect()
            .transition(.scale.combined(with: .opacity))
        }
        .frame(width: 1024, height: 576)
    }
}
