//
//  InsightPlatterView.swift
//  Midoku
//
//  Created by Skitty on 12/17/25.
//

import SwiftUI

struct InsightPlatterView<Content: View>: View {
    @ViewBuilder var content: Content

    private let cornerRadius: CGFloat = 0

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 2)
    }
}
