//
//  MoreIcon.swift
//  Midoku
//
//  Created by Skitty on 9/23/25.
//

import SwiftUI

struct MoreIcon: View {
    /// Flat square (Midoku Web `.icon-btn--glass`), not a liquid glass circle.
    var body: some View {
        MDIconBox(systemImage: "ellipsis", size: 38, glass: true)
    }
}
