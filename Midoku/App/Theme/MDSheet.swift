//
//  MDSheet.swift
//  Midoku
//
//  Midoku Web's bottom sheet chrome: `.sheet__head` (display title, optional mono count, square
//  actions and a close square) and `.sheet__actions--sticky` (ghost Cancel + accent primary).
//

import SwiftUI

/// `.sheet__head`
struct MDSheetHeader<Actions: View>: View {
    let title: String
    var count: Int?
    var onClose: (() -> Void)?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.mdDisplay(21, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.mdText)
                    .lineLimit(2)
                if let count {
                    Text("\(count)")
                        .font(.mdMono(13, weight: .medium))
                        .foregroundStyle(Color.mdText3)
                }
            }
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            HStack(spacing: 8) { actions }
            if let onClose {
                MDIconButton(systemImage: "xmark", label: "Close", action: onClose)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.mdS2)
    }
}

/// One button in the sticky sheet action bar.
struct MDSheetAction {
    let title: String
    var disabled = false
    var destructive = false
    let action: () -> Void
}

/// `.sheet__actions--sticky`
struct MDSheetActions: View {
    var secondary: MDSheetAction?
    let primary: MDSheetAction

    var body: some View {
        HStack(spacing: 10) {
            if let secondary {
                Button(action: secondary.action) {
                    Text(secondary.title).frame(maxWidth: .infinity)
                }
                .buttonStyle(MDGhostButtonStyle(small: false))
                .disabled(secondary.disabled)
            }
            Button(action: primary.action) {
                Text(primary.title)
                    .font(.mdSystem(size: 14, weight: .semibold))
                    .foregroundStyle(primary.destructive ? Color.white : Color(uiColor: MDColor.onAccent))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(primary.destructive ? Color.red : Color.mdAccent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(primary.disabled)
            .opacity(primary.disabled ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.mdS2)
        .overlay(alignment: .top) { Rectangle().fill(Color.mdLine2).frame(height: 1) }
    }
}

private struct MDSheetChrome<Actions: View>: ViewModifier {
    let title: String
    var count: Int?
    var onClose: (() -> Void)?
    var secondary: MDSheetAction?
    var primary: MDSheetAction?
    @ViewBuilder var actions: Actions

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.mdS2.ignoresSafeArea())
            .navigationTitle(title)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                MDSheetHeader(title: title, count: count, onClose: onClose) { actions }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let primary { MDSheetActions(secondary: secondary, primary: primary) }
            }
    }
}

extension View {
    /// Replaces the navigation bar of a sheet's root screen with the web sheet head, and its
    /// Cancel / confirm bar buttons with the sticky action bar.
    func mdSheet<Actions: View>(
        _ title: String,
        count: Int? = nil,
        onClose: (() -> Void)? = nil,
        secondary: MDSheetAction? = nil,
        primary: MDSheetAction? = nil,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        modifier(MDSheetChrome(title: title, count: count, onClose: onClose, secondary: secondary, primary: primary, actions: actions))
    }

    func mdSheet(
        _ title: String,
        count: Int? = nil,
        onClose: (() -> Void)? = nil,
        secondary: MDSheetAction? = nil,
        primary: MDSheetAction? = nil
    ) -> some View {
        modifier(MDSheetChrome(title: title, count: count, onClose: onClose, secondary: secondary, primary: primary) { EmptyView() })
    }
}
