//
//  ContentView.swift
//  IntentRelay
//
//  Created by 蒋招衢 on 2026/4/18.
//

import SwiftUI
import RealityKit

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        ZStack {
            switch appModel.currentState {
            case .main:
                mainContent
            case .chat:
                AIChatView {
                    withAnimation {
                        appModel.currentState = .overallEdit
                    }
                }
                .clipShape(.rect(cornerRadius: 42))
            case .overallEdit:
                OverallEditView {
                    withAnimation {
                        appModel.currentState = .main
                    }
                }
            case .componentEdit:
                ComponentGeneratorView(
                    onDismiss: {
                        withAnimation {
                            appModel.currentState = .main
                        }
                    },
                    onComplete: { selectedImage in
                        print("用户选择了图片: \(selectedImage?.size ?? .zero)")
                        withAnimation {
                            appModel.currentState = .main
                        }
                    }
                )
                .glassBackgroundEffect()
            }
        }
        .task {
            // 启动时自动打开沉浸式空间
            if appModel.immersiveSpaceState == .closed {
                await openImmersiveSpace(id: appModel.immersiveSpaceID)
            }
        }
    }

    private var mainContent: some View {
        VStack{
            VStack(spacing: 30) {
                Text("Welcome to IntentRelay")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                HStack(spacing: 20) {
                    Button(action: {
                        withAnimation(.spring()) {
                            appModel.currentState = .componentEdit
                        }
                    }) {
                        Label("Component Generation", systemImage: "sparkles")
                            .font(.headline)
                            .padding()
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        withAnimation(.spring()) {
                            appModel.currentState = .chat
                        }
                    }) {
                        Label("Overall Generation", systemImage: "sparkles")
                            .font(.headline)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            RecordContentView()
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
