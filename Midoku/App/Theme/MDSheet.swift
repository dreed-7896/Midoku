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

/// One `.menu__row` in an action sheet.
struct MDActionRow: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    var detail: String?
    var destructive = false
    var disabled = false
    /// Runs without closing the sheet (switches and choices).
    var keepsOpen = false
    let action: () -> Void
}

/// Midoku Web's options sheet: a bordered list of rows with a square icon, a title and a detail line.
struct MDActionSheet: View {
    let title: String
    let rows: [MDActionRow]
    let onPick: (MDActionRow) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button { onPick(row) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: row.systemImage)
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(row.destructive ? Color.mdAccent : Color.mdText2)
                                    .frame(width: 36, height: 36)
                                    .background(Color.mdS3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .font(.mdSystem(size: 15, weight: .medium))
                                        .foregroundStyle(row.destructive ? Color.mdAccent : Color.mdText)
                                    if let detail = row.detail {
                                        Text(detail).font(.mdSystem(size: 12)).foregroundStyle(Color.mdText3).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                if !row.keepsOpen {
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mdText3)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minHeight: 60)
                            .background(Color.mdS1)
                            .overlay(alignment: .top) {
                                if index > 0 { Rectangle().fill(Color.mdLine).frame(height: 1) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(row.disabled)
                        .opacity(row.disabled ? 0.5 : 1)
                    }
                }
                .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .mdSheet(title, onClose: onClose)
        }
    }
}

private struct MDActionSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let rows: () -> [MDActionRow]
    @State private var pending: (() -> Void)?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            // Actions that open another sheet run once this one has closed.
            let action = pending
            pending = nil
            action?()
        }) {
            MDActionSheet(title: title, rows: rows(), onPick: { row in
                if row.keepsOpen {
                    row.action()
                } else {
                    pending = row.action
                    isPresented = false
                }
            }, onClose: { isPresented = false })
            .presentationDetents([.medium, .large])
            .midokuAccent()
        }
    }
}

extension View {
    func mdActionSheet(isPresented: Binding<Bool>, title: String, rows: @escaping () -> [MDActionRow]) -> some View {
        modifier(MDActionSheetModifier(isPresented: isPresented, title: title, rows: rows))
    }
}

/// Long press opens a web options sheet instead of the system context menu.
private struct MDLongPressActions: ViewModifier {
    let title: String
    let rows: () -> [MDActionRow]
    var enabled = true
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.45) {
                guard enabled else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                shown = true
            }
            .mdActionSheet(isPresented: $shown, title: title, rows: rows)
    }
}

extension View {
    func mdLongPressActions(_ title: String, enabled: Bool = true, rows: @escaping () -> [MDActionRow]) -> some View {
        modifier(MDLongPressActions(title: title, rows: rows, enabled: enabled))
    }
}

extension UIViewController {
    /// UIKit entry point for the web options sheet; the picked row runs once the sheet has closed.
    func presentMDActionSheet(title: String, rows: [MDActionRow]) {
        var pending: (() -> Void)?
        weak var host: UIViewController?
        let sheet = MDActionSheet(title: title, rows: rows, onPick: { row in
            if row.keepsOpen {
                row.action()
            } else {
                pending = row.action
                host?.dismiss(animated: true) { pending?(); pending = nil }
            }
        }, onClose: { host?.dismiss(animated: true) })
        let controller = UIHostingController(rootView: sheet.midokuAccent())
        host = controller
        if let presentation = controller.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        present(controller, animated: true)
    }
}
