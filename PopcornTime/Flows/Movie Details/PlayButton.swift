//
//  PlayButton.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 21.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit

struct PlayButton: View {
    let theme = Theme()
    @EnvironmentObject private var playbackCoordinator: PlaybackCoordinator
    
    var media: Media
    
    var body: some View {
        SelectTorrentQualityButton(media: media, action: { torrent in
            playbackCoordinator.play(media: media, torrent: torrent)
        }, label: {
            VStack {
                VisualEffectBlur() {
                    Image("Play")
                }
                Text("Play")
            }
        })
        .frame(width: theme.buttonWidth, height: theme.buttonHeight)
    }
}

extension PlayButton {
    struct Theme {
        let buttonWidth: CGFloat = value(tvOS: 142, macOS: 100)
        let buttonHeight: CGFloat = value(tvOS: 115, macOS: 81)
    }
}

struct PlayButton_Previews: PreviewProvider {
    static var previews: some View {
        PlayButton(media: Movie.dummy())
            .environmentObject(PlaybackCoordinator())
            .buttonStyle(TVButtonStyle())
            .padding(40)
            .previewLayout(.fixed(width: 300, height: 300))
            .preferredColorScheme(.dark)
    }
}
