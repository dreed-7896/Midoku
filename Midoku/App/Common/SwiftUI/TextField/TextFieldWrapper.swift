//
//  TextFieldWrapper.swift
//  Midoku
//
//  Created by Skitty on 8/7/25.
//

import SwiftUI

struct TextFieldWrapper<Content: View>: View {
    var hasError: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Color.mdS1)
        .overlay(Rectangle().strokeBorder(hasError ? Color.mdAccent : Color.mdLine, lineWidth: 1))
    }
}
