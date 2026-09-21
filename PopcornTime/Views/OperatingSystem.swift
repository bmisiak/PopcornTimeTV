//
//  OperatingSystem.swift
//  PopcornTime
//
//  Created by Alexandru Tudose on 05.08.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
//#if canImport(UIKit)
//import UIKit
//var lastOrientation: UIDeviceOrientation = .unknown
//#endif

func value<T>(tvOS: T, macOS: T, compactSize: T? = nil, isCompact: Bool = true) -> T {
    #if os(tvOS)
        return tvOS
    #elseif os(macOS)
        return macOS
    #elseif os(iOS)
    
    return isCompact ? compactSize ?? macOS : macOS
    #endif
}

struct CompactSizeClassModifier: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var sizeClass
    #endif
    
    func body(content: Content) -> some View {
        #if os(iOS)
        
        if sizeClass == .compact {
            
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    
    @ViewBuilder
    func hideIfCompactSize() -> some View {
        modifier(CompactSizeClassModifier())
    }
    
    @ViewBuilder
    func hideIfPhone() -> some View {
        modifier(CompactSizeClassModifier())
    }
}
