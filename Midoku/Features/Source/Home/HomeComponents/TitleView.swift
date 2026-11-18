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
                    Image(systemName: "chevron.forward")
                        .font(.mdSubheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
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

    @ViewBuilder
    var titleView: some View {
        if let subtitle {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.mdTitle3)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.mdSubheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(title)
                .font(.mdTitle3)
                .fontWeight(.semibold)
        }
    }
}
