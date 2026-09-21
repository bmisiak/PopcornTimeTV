//
//  PersonDetailsViewModel.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 04.07.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit

class PersonDetailsViewModel: ObservableObject, MediaPosterLoader {
    var person: Person
    
    @Published var isLoading = false
    var didLoad = false
    
    @Published var error: Error?
    @Published var shows: [Show] = []
    @Published var movies: [Movie] = []
    
    init(person: Person) {
        self.person = person
    }
    
    func load() {
        guard !isLoading && !didLoad else {
            return
        }
        
        isLoading = true
        Task { @MainActor in
            do {
                async let moviesCredits = PopcornKit.getMovieCredits(for: person)
                async let showCredits = PopcornKit.getShowCredits(for: person)
                self.movies = try await moviesCredits
                self.shows = try await showCredits
                self.didLoad = true
            } catch {
                self.error = error
            }
            
            self.isLoading = false
        }
    }
}
