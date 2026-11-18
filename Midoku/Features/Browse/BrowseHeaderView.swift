//
//  BrowseHeaderView.swift
//  Midoku
//
//  Midoku Web's Sources page head for the Extensions list: back square, mono kicker over the
//  display title with square actions, then the search field.
//

import SwiftUI

struct BrowseHeaderView: View {
    var installedCount = 0
    var editing = false
    @Binding var search: String

    var onBack: () -> Void = {}
    var onAdd: () -> Void = {}
    var onMigrate: () -> Void = {}
    var onDone: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MDIconButton(systemImage: "chevron.left", label: "Back", action: onBack)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            MDPageHeader(kicker: "\(installedCount) installed · On this device", title: "Extensions") {
                if editing {
                    Button("Done", action: onDone)
                        .buttonStyle(MDGhostButtonStyle(small: false))
                } else {
                    MDIconButton(systemImage: "arrow.left.arrow.right", label: NSLocalizedString("MIGRATE_SOURCES"), action: onMigrate)
                    MDIconButton(systemImage: "plus", label: NSLocalizedString("ADD_SOURCE"), action: onAdd)
                }
            }

            MDSearchField(text: $search, prompt: "Search extensions", autofocus: false)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mdBg)
    }
}
