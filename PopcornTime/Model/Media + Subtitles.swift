//
//  Media + Subtitles.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 21.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import Foundation
import PopcornKit

extension Media {
    /**
     Retrieves subtitles from OpenSubtitles
     
     - Parameter id:    `nil` by default. The imdb id of the media will be used by default.
     */
    func getSubtitles(forId id: String? = nil, orWithFilePath: URL? = nil) async throws -> Dictionary<String, [Subtitle]> {
        let id = id ?? self.id
        if let filePath = orWithFilePath {
            return try await SubtitlesApi.shared.search(preferredLang: "el", videoFilePath: filePath)
        } else if let episode = self as? Episode, !id.hasPrefix("tt"), episode.show != nil {
            return try await SubtitlesApi.shared.search(episode)
        } else {
            return try await SubtitlesApi.shared.search(imdbId: id)
        }
    }
}
