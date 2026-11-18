//
//  TitleView.swift
//  Midoku
//
//  Created by Skitty on 12/30/24.
//

import SwiftUI

struct TitleView: View {
    let title: String
    var subtitle: String?
    var onTitleClick: (() -> Void)?

    var body: some View {
        if let onTitleClick {
            Button {
                onTitleClick()
            } label: {
                HStack {
                    titleView
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mdText3)
                }
                .contentShape(Rectangle())
            }
            .padding(.horizontal)
            .buttonStyle(.plain)
        } else {
            HStack {
                titleView
                Spacer()
            }
            .padding(.horizontal)
        }
    }

    /// `.section-head .h2`: display title, muted subtitle.
    @ViewBuilder
    var titleView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.mdDisplay(21, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Color.mdText)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.mdSystem(size: 13))
                    .foregroundStyle(Color.mdText3)
                    .lineLimit(2)
            }
        }
    }
}
