//
//  PopcornTimetvOS_SwiftUIApp.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 19.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornTorrent


@main
struct PopcornTime: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
//        #if os(iOS) || os(macOS)
//        .commands(content: {
//            OpenCommand()
//        })
//        #endif
        
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
//        .windowToolbarStyle(.expanded)
        #endif
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif

    }

// in order do exit app on window close
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }
    }
#endif
}

private struct AppRootView: View {
    @StateObject private var playbackCoordinator = PlaybackCoordinator()

    var body: some View {
        NavigationStack {
            TabBarView()
                .modifier(AcceptTermsOfService())
            #if os(iOS) || os(macOS)
                .modifier(MagnetTorrentLinkOpener())
            #elseif os(tvOS)
                .modifier(TopShelfLinkOpener())
            #endif
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        PTTorrentsSession.shared()
                    }
                }
        }
        .environmentObject(playbackCoordinator)
        .fullScreenContent(
            item: $playbackCoordinator.request,
            title: playbackCoordinator.request?.media.title ?? ""
        ) { request in
            TorrentPlayerView(
                torrent: request.torrent,
                media: request.media,
                nextEpisode: request.nextEpisode
            )
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        .accentColor(.white)
        .navigationViewStyle(StackNavigationViewStyle())
        .modifier(SecondaryScreen())
        #endif
    }
}
