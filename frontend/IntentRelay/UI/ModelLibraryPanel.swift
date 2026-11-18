import SwiftUI
import RealityKit
import UIKit

struct ModelLibraryPanel: View {
    @Bindable var viewModel: UIBoardViewModel
    var appModel: AppModel
    @ObservedObject private var entityManager = GlobalEntityManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("3D Model Library")
                    .font(.headline)
                Spacer()
                Button {
                    clearPlacedModels()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation {
                        viewModel.isShowingModelLibrary = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if appModel.isLoadingModels {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if appModel.backendModels.isEmpty {
                Text("No Models")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(appModel.backendModels) { model in
                            if model.has3DModel {
                                ModelGridItem(model: model, appModel: appModel)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(height: 300)
            }
        }
        .padding()
        .frame(width: 280)
        .glassBackgroundEffect()
        .task {
            await appModel.fetchModelsList()
        }
    }

    private func clearPlacedModels() {
        for child in entityManager.creationEntity.children {
            child.removeFromParent()
        }
        appModel.addedModels.removeAll()
    }
}

/// 网格项：显示部件图片，点击后放置 3D 模型
struct ModelGridItem: View {
    let model: ModelItem
    var appModel: AppModel
    @State private var thumbnailImage: UIImage? = nil

    var body: some View {
        Button {
            // 点击后放置 3D 模型到场景中
            if let modelURL = model.modelURL {
                let fullURL = modelURL.hasPrefix("http") ? modelURL : BackendAPI.shared.baseURL + modelURL
                let generatedModel = AppModel.GeneratedModel(
                    name: model.name,
                    color: .systemBlue,
                    modelURL: fullURL
                )
                appModel.addedModels.append(generatedModel)
            }
        } label: {
            VStack(spacing: 6) {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay(ProgressView().scaleEffect(0.6))
                }

                Text(model.name)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .task {
            guard thumbnailImage == nil,
                  let url = URL(string: model.imageURL.hasPrefix("http") ? model.imageURL : BackendAPI.shared.baseURL + model.imageURL) else { return }
            if let data = try? await URLSession.shared.data(from: url).0,
               let image = UIImage(data: data) {
                thumbnailImage = image
            }
        }
    }
}
