//
//  DoneButton.swift
//  Midoku
//
//  Created by Skitty on 9/21/25.
//

import SwiftUI

struct DoneButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(NSLocalizedString("DONE"))
                .font(.mdSystem(size: 14, weight: .semibold))
                .foregroundStyle(Color(uiColor: MDColor.onAccent))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Color.mdAccent)
        }
        .buttonStyle(.plain)
    }
}
