//
//  DownloadProgressView.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 25.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI

struct DownloadProgressView: View {
    let progress: Float
    #if os(tvOS) || os(iOS)
    #if os(tvOS)
    let lineWidth: CGFloat = 10
    let outlineWidth: CGFloat = 5
    #else
    let lineWidth: CGFloat = 3
    let outlineWidth: CGFloat = 1
    #endif
    #else
    let lineWidth: CGFloat = 3
    let outlineWidth: CGFloat = 1
    #endif
    
    struct PieView: Shape {
        var progress: Float
        var lineWidth: CGFloat
        var isFilled = true
        
        func path(in rect: CGRect) -> Path {
            let center = CGPoint(x: rect.width * 0.5, y: rect.height * 0.5)
            return Path({ path in
                if isFilled {
                    path.move(to: center)
                }
                path.addArc(center: center,
                            radius: Swift.min(center.x, center.y) - (lineWidth * 0.5),
                            startAngle: .degrees(-90),
                            endAngle: .degrees(Double(progress) * 360 - 90),
                            clockwise: false)
                path.closeSubpath()
            })
        }
    }

    var body: some View {
        ZStack {
            PieView(progress: 1.0, lineWidth: lineWidth, isFilled: false)
                .stroke(lineWidth: outlineWidth)
            PieView(progress: progress, lineWidth: lineWidth)
                .fill()
        }.foregroundColor(Color.white)
    }
    
}

struct DownloadProgressView_Previews: PreviewProvider {
    static var previews: some View {
        DownloadProgressView(progress: 0.4)
            .frame(width: 200, height: 100)
            .previewLayout(PreviewLayout.sizeThatFits)
    }
}
