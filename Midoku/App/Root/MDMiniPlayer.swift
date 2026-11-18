//
//  MDMiniPlayer.swift
//  Midoku
//
//  Midoku Web's `.mini`: a floating "continue reading" card above the tab bar. Dismissable;
//  it comes back after the next reading session.
//

import SwiftUI

@MainActor
enum MDMiniPlayer {
    static let dismissedKey = "Midoku.miniDismissedAt"

    /// The library entry read most recently, unless the card was dismissed after that read.
    static func current(in store: MCCollectionStore = .shared) -> MCPersonalEntry? {
        let dismissed = UserDefaults.standard.double(forKey: dismissedKey)
        return store.library.entries
            .filter { ($0.lastReadAt?.timeIntervalSince1970 ?? 0) > dismissed }
            .max { ($0.lastReadAt ?? .distantPast) < ($1.lastReadAt ?? .distantPast) }
    }
}

struct MDMiniPlayerView: View {
    var openEntry: (UUID) -> Void
    var resume: (UUID) -> Void
    @State private var store = MCCollectionStore.shared
    @AppStorage(MDMiniPlayer.dismissedKey) private var dismissedAt: Double = 0

    var body: some View {
        // Reads `dismissedAt` so the card hides as soon as it is dismissed.
        let _ = dismissedAt
        if let entry = MDMiniPlayer.current(in: store) {
            let title = store.library.title(entry)
            let art = MDCoverArt.art(for: title)
            HStack(spacing: 6) {
                Button { openEntry(entry.id) } label: {
                    HStack(spacing: 12) {
                        MCEntryCover(entry: entry).frame(width: 32, height: 48).clipped()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.mdSystem(size: 14, weight: .semibold)).foregroundStyle(Color.mdText).lineLimit(1)
                            Text("Continue · \((entry.lastReadAt ?? .now).formatted(.relative(presentation: .named)))")
                                .font(.mdMono(11.5, weight: .medium))
                                .foregroundStyle(Color(red: 244 / 255, green: 244 / 255, blue: 246 / 255).opacity(0.78))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(title)")
                Button { resume(entry.id) } label: {
                    Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(uiColor: MDColor.onAccent))
                        .frame(width: 44, height: 44)
                        .background(Color.mdText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume \(title)")
                Button { dismissedAt = Date.now.timeIntervalSince1970 } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 244 / 255, green: 244 / 255, blue: 246 / 255).opacity(0.8))
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 60)
            .background(MDCoverArt.color(art.c1))
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 17, y: 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
