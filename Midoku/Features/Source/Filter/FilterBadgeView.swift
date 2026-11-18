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

    var body: some View {
        Text(String(count))
            .font(.mdMono(11, weight: .bold))
            .padding(.horizontal, 4)
            .frame(minWidth: Self.size)
            .frame(height: Self.size)
            .foregroundStyle(Color(uiColor: MDColor.onAccent))
            .background(Color.mdAccent)
    }
}
