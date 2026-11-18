//
//  ListingsHeaderView.swift
//  Midoku
//
//  Created by Skitty on 2/14/24.
//

import SwiftUI
import AidokuRunner

struct ListingsHeaderView: View {
    let source: AidokuRunner.Source
    @Binding var listings: [AidokuRunner.Listing]
    @Binding var selectedListing: Int

    @State private var error: Error?
    @State private var listingsLoaded: Bool = false

    var body: some View {
        Group {
            if let error {
                MDEmpty(systemImage: "exclamationmark.triangle", title: "Couldn’t load listings",
                        detail: Text(error.midokuDescription()), tone: .error, compact: true)
                    .padding(.horizontal, 16)
            } else if !listings.isEmpty || listingsLoaded {
                headerScrollView
                    .transition(.opacity)
            } else {
                Self.placeholder
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("refresh-listings"))) { _ in
            listingsLoaded = false
            self.error = nil
            Task {
                await load()
            }
        }
        .task {
            if listings.isEmpty {
                await load()
            }
        }
    }

    func load() async {
        do {
            let newListings = try await source.getListings()
            withAnimation {
                listings = newListings
                listingsLoaded = true
            }
        } catch {
            withAnimation {
                self.error = error
            }
        }
    }

    /// `.underline-tabs`: Home (when the source has one) and each listing.
    var headerScrollView: some View {
        let options = if source.features.providesHome {
            [NSLocalizedString("HOME")] + listings.map { $0.name }
        } else {
            listings.map { $0.name }
        }
        return MDUnderlineTabs {
            ForEach(options.indices, id: \.self) { offset in
                MDUnderlineTab(title: options[offset], on: selectedListing == offset) {
                    selectedListing = offset
                }
            }
        }
    }

    static var placeholder: some View {
        HStack(spacing: 24) {
            ForEach(0..<3) { _ in
                MDSkeleton().frame(width: 64, height: 14)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.mdLine).frame(height: 1) }
        .transition(.opacity)
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    @Previewable @State var selectedListing = 0
    @Previewable @State var listings: [AidokuRunner.Listing] = [
        .init(id: "1", name: "Listing 1"),
        .init(id: "2", name: "Listing 2")
    ]
    ListingsHeaderView(
        source: .demo(),
        listings: $listings,
        selectedListing: $selectedListing
    )
    .padding()
}
