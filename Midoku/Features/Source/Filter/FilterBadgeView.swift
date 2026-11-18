//
//  FilterBadgeView.swift
//  Midoku
//
//  Created by Skitty on 10/16/23.
//

import SwiftUI

struct FilterBadgeView: View {
    let count: Int

    static let size: CGFloat = 18

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(String(count))
            .padding(.horizontal, 5)
            .frame(minWidth: Self.size)
            .frame(height: Self.size)
            .foregroundColor(colorScheme == .light ? .white : .accentColor)
            .background {
                RoundedRectangle(cornerRadius: 0)
                    .foregroundColor(colorScheme == .light ? .accentColor : .white)
            }
    }
}
