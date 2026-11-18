//
//  MDComponents.swift
//  Midoku
//
//  SwiftUI versions of Midoku Web's building blocks (src/styles.css):
//  page head, square icon buttons, chips, search field, section labels, progress bar.
//

import SwiftUI

extension Font {
    /// Bricolage Grotesque at an exact size (web `--display`).
    static func mdDisplay(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        guard MDFont.available else { return .system(size: size, weight: weight) }
        let name = weight == .heavy || weight == .black ? "BricolageGrotesque-ExtraBold"
            : weight == .bold ? "BricolageGrotesque-Bold" : "BricolageGrotesque-SemiBold"
        return .custom(name, size: size, relativeTo: .largeTitle)
    }
}

/// `.page-head`: mono kicker over a 40pt display title, square actions on the right.
struct MDPageHeader<Actions: View>: View {
    var kicker: String?
    let title: String
    @ViewBuilder var actions: Actions

    init(kicker: String? = nil, title: String, @ViewBuilder actions: () -> Actions) {
        self.kicker = kicker
        self.title = title
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let kicker {
                    Text(kicker)
                        .font(.mdMono(12, weight: .medium))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(Color.mdText3)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.mdDisplay(40))
                    .tracking(-1.4)
                    .foregroundStyle(Color.mdText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) { actions }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}

extension MDPageHeader where Actions == EmptyView {
    init(kicker: String? = nil, title: String) {
        self.init(kicker: kicker, title: title) { EmptyView() }
    }
}

/// `.icon-btn`: 44pt square, raised surface, hairline border. Use as a Button or Menu label.
struct MDIconBox: View {
    let systemImage: String
    var active = false
    var badge: Int?
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size > 40 ? 18 : 15, weight: .medium))
            .foregroundStyle(active ? Color.mdAccent : Color.mdText)
            .frame(width: size, height: size)
            .background(Color.mdS1)
            .overlay(Rectangle().strokeBorder(active ? Color.mdAccent : Color.mdLine, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.mdMono(11, weight: .bold))
                        .foregroundStyle(Color(uiColor: MDColor.onAccent))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.mdAccent)
                        .offset(x: 6, y: -6)
                }
            }
            .contentShape(Rectangle())
    }
}

struct MDIconButton: View {
    let systemImage: String
    let label: String
    var active = false
    var badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) { MDIconBox(systemImage: systemImage, active: active, badge: badge) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

/// `.chip` / `.chip--lg`: square tab or filter chip; the selected one is filled white.
struct MDChip: View {
    let title: String
    var count: Int?
    var active = false
    var systemImage: String?
    var large = true
    var dashed = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)) }
            if !title.isEmpty {
                Text(title)
                    .font(.mdSystem(size: large ? 14 : 13, weight: active ? .semibold : .medium))
                    .lineLimit(1)
            }
            if let count {
                Text("\(count)").font(.mdMono(12, weight: .medium)).opacity(0.6)
            }
        }
        .foregroundStyle(active ? Color(uiColor: MDColor.onAccent) : Color.mdText2)
        .padding(.horizontal, large ? 14 : 12)
        .frame(height: large ? 38 : 34)
        .background(active ? Color.mdText : Color.clear)
        .overlay(
            Rectangle().strokeBorder(active ? Color.mdText : Color.mdLine2,
                                     style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : []))
        )
        .contentShape(Rectangle())
    }
}

/// `.field`: search / text field row.
struct MDSearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var autofocus = true
    var onClose: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
            TextField(prompt, text: $text)
                .font(.mdSystem(size: 16))
                .foregroundStyle(Color.mdText)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if let onClose {
                Button {
                    text = ""
                    onClose()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
        }
        .foregroundStyle(focused ? Color.mdText : Color.mdText3)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.mdS1)
        .overlay(Rectangle().strokeBorder(focused ? Color.mdAccent : Color.mdLine, lineWidth: 1))
        .onAppear { if autofocus { focused = true } }
    }
}

/// `.label`: mono uppercase section label.
struct MDSectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mdMono(11))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Color.mdText3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `.thumb__bar`: 4pt reading progress along the bottom of a cover.
struct MDProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.55))
                Rectangle().fill(Color.mdText).frame(width: geometry.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 4)
    }
}

/// `.badge`: square accent count badge (mono).
struct MDBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mdMono(11, weight: .bold))
            .foregroundStyle(Color(uiColor: MDColor.onAccent))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color.mdAccent)
    }
}
