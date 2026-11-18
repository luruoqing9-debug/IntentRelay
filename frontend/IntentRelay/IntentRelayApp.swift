//
//  IntentRelayApp.swift
//  IntentRelay
//
//  Created by 蒋招衢 on 2026/4/18.
//

import SwiftUI

@main
struct IntentRelayApp: App {
    
    @State private var appModel = AppModel()
    init(){
        UIBoardSystem.registerSystem()
        
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
