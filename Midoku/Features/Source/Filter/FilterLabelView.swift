//
//  FilterLabelView.swift
//  Midoku
//
//  Created by Skitty on 10/16/23.
//

import SwiftUI

struct FilterLabelView: View {
    let name: String
    var badgeCount: Int?
    var active = false
    var chevron = true
    var icon: String?

    private var highlighted: Bool {
        active || badgeCount ?? 0 > 0
    }

    // show badge if count (number of subfilters enabled) is greater than 1
    private var hasBadge: Bool {
        badgeCount ?? 1 > 1
    }

    var body: some View {
        // `.chip`: square, hairline border; filled white while a value is picked.
        HStack(spacing: 5) {
            if let badgeCount, hasBadge {
                FilterBadgeView(count: badgeCount)
            }
            Text(name)
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            } else if chevron {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).opacity(0.7)
            }
        }
        .lineLimit(1)
        .font(.mdSystem(size: 13, weight: highlighted ? .semibold : .medium))
        .foregroundStyle(highlighted ? Color(uiColor: MDColor.onAccent) : Color.mdText2)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(highlighted ? Color.mdText : Color.clear)
        .overlay(Rectangle().strokeBorder(highlighted ? Color.mdText : Color.mdLine2, lineWidth: 1))
        .contentShape(Rectangle())
    }
}
