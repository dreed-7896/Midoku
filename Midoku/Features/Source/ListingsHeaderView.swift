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

    var headerScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let options = if source.features.providesHome {
                    [NSLocalizedString("HOME")] + listings.map { $0.name }
                } else {
                    listings.map { $0.name }
                }
                ForEach(options.indices, id: \.self) { offset in
                    let option = options[offset]
                    let active = selectedListing == offset
                    Button {
                        selectedListing = offset
                    } label: {
                        MDChip(title: option, active: active, large: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .scrollClipDisabledPlease()
        .padding(.top, -11)
    }

    static var placeholder: some View {
        // skeleton loading
        HStack(spacing: 8) {
            ForEach(0..<3) { _ in
                MDSkeleton().frame(width: 84, height: 34)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, -11)
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
