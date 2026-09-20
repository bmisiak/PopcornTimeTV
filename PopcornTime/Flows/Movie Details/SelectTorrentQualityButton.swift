//
//  SelectTorrentQualityAction.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 24.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit
import Network

let networkMonitor = NWPathMonitor()

struct SelectTorrentQualityButton<Label>: View where Label : View {
    var media: Media
    var action: (Torrent) -> Void
    @ViewBuilder var label: () -> Label
    
    struct AlertType: Identifiable {
        enum Choice {
            case noTorrentsFound, streamOnCellular, streamProviderError
        }

        var id: Choice
    }

    
    @State var showChooseQualityActionSheet = false
    @State var alert: AlertType?
    @State private var resolvedTorrents: [Torrent] = []
    @State private var streamProviderError: String?
    
    var body: some View {
        return Button(action: {
            if !Session.streamOnCellular && networkMonitor.currentPath.isExpensive {
                alert = .init(id: .streamOnCellular)
                return
            }
            
            if availableTorrents.isEmpty {
                Task { await resolveStreams() }
            } else {
                presentStreams()
            }
        }, label: label)
        #if os(iOS) || os(tvOS)
        .confirmationDialog("Choose Quality", isPresented: $showChooseQualityActionSheet, titleVisibility: .visible, actions: {
            chooseTorrentsButtons
        })
        #elseif os(macOS)
        .popover(isPresented: $showChooseQualityActionSheet, content: {
            VStack {
                Text("Choose Quality")
                chooseTorrentsButtons
                    .controlSize(.large)
            }
            .font(.system(size: 16))
            .padding(20)
        })
        #endif
        .alert(item: $alert) { alert in
            switch alert.id {
            case .noTorrentsFound:
                return Alert(title: Text("No torrents found"),
                      message: Text("Torrents could not be found for the specified media."))
            case .streamOnCellular:
                return Alert(title: Text("Cellular Data is turned off for streaming"),
                      message: nil,
                      primaryButton: .default(Text("Turn On")) {
                        Session.streamOnCellular = true
                      },
                      secondaryButton: .cancel())
            case .streamProviderError:
                return Alert(title: Text("Unable to find torrents"),
                             message: Text(streamProviderError ?? "The stream provider is temporarily unavailable."))
            }
            
        }
        .onAppear {
            if networkMonitor.queue == nil {
                networkMonitor.start(queue: .global())
            }
        }
    }
    
    var autoSelectTorrent: Torrent? {
        if let quality = Session.autoSelectQuality {
            let sorted  = availableTorrents.sorted(by: <)
            let torrent = quality == "Highest" ? sorted.last! : sorted.first!
            return torrent
        }
        
        #if os(tvOS)
        if availableTorrents.count == 1 {
            return availableTorrents[0]
        }
        #endif
        
        return nil
    }

    @ViewBuilder
    var chooseTorrentsButtons: some View {
        ForEach(availableTorrents.sorted(by: >)) { torrent in
            Button {
                action(torrent)
            } label: {
                #if os(iOS) || os(tvOS)
                Text(torrent.quality) +
                Text(" (seeds: \(torrent.seeds) - peers: \(torrent.peers))")
                #elseif os(macOS)
                torrent.health.image
                Text(torrent.quality)
                    .fontWeight(.bold)
                Text(" (seeds: \(torrent.seeds) - peers: \(torrent.peers))")
                    .foregroundColor(.appLightGray)
                    .font(.system(size: 12, weight: .light))
                Spacer()
                #endif
            }
        }
    }

    private var availableTorrents: [Torrent] {
        resolvedTorrents.isEmpty ? media.torrents : resolvedTorrents
    }

    @MainActor
    private func resolveStreams() async {
        do {
            resolvedTorrents = try await TorrentioApi.shared.streams(for: media)
            presentStreams()
        } catch TorrentioError.noStreams {
            alert = .init(id: .noTorrentsFound)
        } catch {
            streamProviderError = error.localizedDescription
            alert = .init(id: .streamProviderError)
        }
    }

    private func presentStreams() {
        if let torrent = autoSelectTorrent {
            action(torrent)
        } else {
            showChooseQualityActionSheet = true
        }
    }
}

struct SelectTorrentQualityAction_Previews: PreviewProvider {
    static var previews: some View {
        SelectTorrentQualityButton(media: Movie.dummy(), action: { torrent in
            print("selected: ", torrent)
        }, label: {
            Text("Play")
        })
            .preferredColorScheme(.dark)
    }
}
