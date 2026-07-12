//
//  tsjy_VApp.swift
//  tsjy-V
//
//  Created by Peng Yixing on 2026/5/12.
//

import SwiftUI

@main
struct tsjy_VApp: App {
    @State private var appModel = AppModel()

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
        .immersionStyle(selection: .constant(.full), in: .full)

        WindowGroup(id: "webViewWindow", for: String.self) { $sourceID in
            WebViewWindow(sourceID: sourceID ?? "")
                .environment(appModel)
        }
        .defaultSize(width: 1000, height: 700)

        WindowGroup(id: "videoWindow", for: String.self) { $sourceID in
            VideoWindow(sourceID: sourceID ?? "")
                .environment(appModel)
        }
        .defaultSize(width: 960, height: 620)

        WindowGroup(id: "controlWindow") {
            DeviceControlWindow()
                .environment(appModel)
        }
        .defaultSize(width: 1280, height: 840)
    }
}
