//
//  SecondaryScreen.swift
//  PopcornTime
//
//  Created by Alexandru Tudose on 04.10.2022.
//  Copyright © 2022 PopcornTime. All rights reserved.
//

import SwiftUI

@MainActor
final class ExternalDisplayContent: ObservableObject {
    static let shared = ExternalDisplayContent()

    @Published var view: AnyView?
    @Published var isShowingOnExternalDisplay = false

    private var connectedSceneIdentifiers = Set<String>()

    func sceneDidConnect(_ session: UISceneSession) {
        connectedSceneIdentifiers.insert(session.persistentIdentifier)
        isShowingOnExternalDisplay = !connectedSceneIdentifiers.isEmpty
    }

    func sceneDidDisconnect(_ session: UISceneSession) {
        connectedSceneIdentifiers.remove(session.persistentIdentifier)
        isShowingOnExternalDisplay = !connectedSceneIdentifiers.isEmpty
    }
}

struct SecondaryScreen: ViewModifier {
    @StateObject private var displayContent = ExternalDisplayContent.shared
    
    func body(content: Content) -> some View {
        content
            .environmentObject(displayContent)
    }
}

@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard session.role == .windowExternalDisplayNonInteractive,
              let windowScene = scene as? UIWindowScene else {
            return
        }

        let displayContent = ExternalDisplayContent.shared
        let window = UIWindow(windowScene: windowScene)
        windowScene.screen.overscanCompensation = .scale
        let view = ExternalView()
            .environmentObject(displayContent)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        self.window = window
        displayContent.sceneDidConnect(session)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplayContent.shared.sceneDidDisconnect(scene.session)
        window = nil
    }
}
