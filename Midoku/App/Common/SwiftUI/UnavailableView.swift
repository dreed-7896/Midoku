//
//  UnavailableView.swift
//  Midoku
//
//  Created by Skitty on 9/23/25.
//

import SwiftUI

/// Empty state in Midoku Web's look (`<Empty>`): a dashed card at the top of the page.
struct UnavailableView: View {
    let title: String
    let systemImage: String
    var description: Text?
    var action: MDStateAction?
    var tone: MDTone = .neutral

    init(_ title: String, systemImage: String, description: Text? = nil, action: MDStateAction? = nil, tone: MDTone = .neutral) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.action = action
        self.tone = tone
    }

    var body: some View {
        MDEmptyPage(systemImage: systemImage, title: title, detail: description, action: action, tone: tone)
    }

    static func search(text: String) -> some View {
        Self(
            String(format: NSLocalizedString("NO_RESULTS_FOR_%@"), text),
            systemImage: "magnifyingglass",
            description: Text(NSLocalizedString("NO_RESULTS_TEXT"))
        )
    }
}
