//
//  CloseButton.swift
//  Midoku
//
//  Created by Skitty on 12/31/24.
//

import SwiftUI

struct CloseButton: View {
    let action: () -> Void

    /// A flat square × (Midoku Web `.icon-btn`), not the system glass close button.
    var body: some View {
        Button(action: action) {
            MDIconBox(systemImage: "xmark", size: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("CLOSE"))
    }
}

struct CloseButtonUIKit: UIViewRepresentable {
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    func makeUIView(context: Context) -> UIButton {
        UIButton(type: .close, primaryAction: UIAction { _ in action() })
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
