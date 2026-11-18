//
//  MDEntryComponents.swift
//  Midoku
//
//  Midoku Web's title page (src/pages/Entry.tsx, `.entry*`, `.facts`, `.ch-row` in styles.css), shared by the
//  library entry screen and the source title screen so both look the same.
//

import SwiftUI

/// `.entry__backdrop`: the cover's colours blurred behind the top of the page, fading into the background.
struct MDEntryBackdrop<Cover: View>: View {
    @ViewBuilder var cover: Cover

    /// The cover across the full screen width behind the hero, softly blurred and fading into the page.
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.mdBg
                cover
                    .frame(width: geometry.size.width, height: 470)
                    .clipped()
                    .blur(radius: 14)
                    .opacity(0.6)
                LinearGradient(colors: [Color.mdBg.opacity(0.15), Color.mdBg.opacity(0.55), Color.mdBg],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: geometry.size.width, height: 470, alignment: .top)
            .clipped()
        }
        .frame(height: 470)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// `.entry__hero`: 156pt cover with a deep shadow, 31pt display title and the author, centred.
struct MDEntryHero<Cover: View, Byline: View>: View {
    let title: String
    var onCover: () -> Void = {}
    var onTitleHold: (() -> Void)?
    @ViewBuilder var cover: Cover
    @ViewBuilder var byline: Byline

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onCover) {
                cover
                    .frame(width: 156, height: 234)
                    .clipped()
                    .shadow(color: .black.opacity(0.55), radius: 25, y: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View cover")
            Text(title)
                .font(.mdDisplay(31, weight: .heavy))
                .tracking(-0.9)
                .lineSpacing(-2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.mdText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .contentShape(Rectangle())
                .onLongPressGesture { onTitleHold?() }
            byline
                .font(.mdSystem(size: 14))
                .foregroundStyle(Color.mdText2)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }
}

/// `.btn--accent.btn--xl` with `.btn__stack`: the Resume / Start reading button with a second line.
struct MDResumeButton: View {
    let title: String
    var subtitle: String?
    var systemImage = "play.fill"
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.mdSystem(size: 15, weight: .bold)).lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.mdSystem(size: 12, weight: .semibold)).opacity(0.75).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(Color(uiColor: MDColor.onAccent))
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 12)
            .background(Color.mdAccent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

/// `.entry__actions .icon-btn`: 56pt square action; accent outline when on.
struct MDSquareAction: View {
    let systemImage: String
    let label: String
    var active = false
    var spinning = false
    var action: () -> Void = {}
    var onHold: (() -> Void)?

    var body: some View {
        MDIconBox(systemImage: systemImage, active: active, size: 56)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spinning)
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.45) { onHold?() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// One cell of `.facts`.
struct MDFact: View {
    let label: String
    var value: String
    var valueColor: Color = .mdText
    var dot: Color?
    var note: String?
    var progress: Double?
    var action: (() -> Void)?

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.mdMono(10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.mdText3)
                .lineLimit(1)
            HStack(spacing: 6) {
                if let dot { Rectangle().fill(dot).frame(width: 7, height: 7) }
                Text(value)
                    .font(.mdDisplay(17, weight: .bold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.mdLine2)
                        Rectangle().fill(Color.mdAccent).frame(width: geometry.size.width * max(0, min(1, progress)))
                    }
                }
                .frame(height: 4)
                .padding(.top, 2)
            }
            if let note {
                Text(note).font(.mdSystem(size: 11)).foregroundStyle(Color.mdAccent).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mdS1)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }.buttonStyle(MDPressedFill())
        } else {
            content
        }
    }
}

private struct MDPressedFill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.overlay(Color.mdS2.opacity(configuration.isPressed ? 0.6 : 0))
    }
}

/// `.facts`: a 3-column grid of facts separated by hairlines.
struct MDFactGrid: View {
    let facts: [MDFact]

    var body: some View {
        let rows = stride(from: 0, to: facts.count, by: 3).map { Array(facts[$0..<min($0 + 3, facts.count)]) }
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index].indices, id: \.self) { column in rows[index][column] }
                    ForEach(0..<(3 - rows[index].count), id: \.self) { _ in Color.mdS1 }
                }
            }
        }
        .background(Color.mdLine)
        .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
    }
}

/// `.desc` with More / Less.
struct MDDescription: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.mdSystem(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Color.mdText2)
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(expanded ? "Less" : "More") { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } }
                .font(.mdSystem(size: 14, weight: .semibold))
                .foregroundStyle(Color.mdAccent)
                .padding(.vertical, 6)
                .buttonStyle(.plain)
        }
    }
}

/// `.tag`: outlined genre chip.
struct MDTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mdSystem(size: 12, weight: .medium))
            .foregroundStyle(Color.mdText2)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .overlay(Rectangle().strokeBorder(Color.mdLine2, lineWidth: 1))
    }
}

/// `.section-head` with `.h2` and a mono count.
struct MDSectionHead<Actions: View>: View {
    let title: String
    var count: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.mdDisplay(21, weight: .bold)).tracking(-0.3).foregroundStyle(Color.mdText)
                if let count { Text(count).font(.mdMono(13, weight: .medium)).foregroundStyle(Color.mdText3) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) { actions }
        }
    }
}

/// `.badge` inside a chapter row ("New", "+3 pages", "Part").
struct MDRowBadge: View {
    let text: String
    var glass = false
    var body: some View {
        Text(text)
            .font(.mdMono(10, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(glass ? Color.mdText : Color(uiColor: MDColor.onAccent))
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(glass ? Color.white.opacity(0.12) : Color.mdAccent)
    }
}

/// `.ch-row`: a chapter as a list row. Current chapter = accent rule on the left; read ones get a check mark.
struct MDChapterRow<Badges: View, Trailing: View>: View {
    let label: String
    var meta: String?
    var read = false
    var current = false
    var selected = false
    var progress: Double?
    @ViewBuilder var badges: Badges
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.mdSystem(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mdText)
                        .lineLimit(1)
                    badges
                }
                if let meta, !meta.isEmpty {
                    Text(meta)
                        .font(.mdSystem(size: 12))
                        .foregroundStyle(Color.mdText3)
                        .lineLimit(1)
                }
                if let progress, progress > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.mdLine2)
                            Rectangle().fill(Color.mdAccent).frame(width: geometry.size.width * min(1, progress))
                        }
                    }
                    .frame(maxWidth: 160)
                    .frame(height: 2)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                trailing
                if read {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.mdMint)
                        .frame(width: 22, height: 22)
                        .accessibilityLabel("Read")
                }
            }
                .foregroundStyle(Color.mdText2)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .background(selected ? Color.mdS2 : Color.clear)
        .overlay(alignment: .leading) { Rectangle().fill(current ? Color.mdAccent : Color.clear).frame(width: 3) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.mdLine).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

extension MDChapterRow where Badges == EmptyView {
    init(label: String, meta: String? = nil, read: Bool = false, current: Bool = false, selected: Bool = false,
         progress: Double? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(label: label, meta: meta, read: read, current: current, selected: selected, progress: progress,
                  badges: { EmptyView() }, trailing: trailing)
    }
}

/// `.chapter__check`: square selection mark.
struct MDCheck: View {
    let on: Bool
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(on ? Color(uiColor: MDColor.onAccent) : Color.clear)
            .frame(width: 24, height: 24)
            .background(on ? Color.mdText : Color.black.opacity(0.35))
            .overlay(Rectangle().strokeBorder(Color.mdText, lineWidth: 2))
            .accessibilityLabel(on ? "Selected" : "Not selected")
    }
}

/// `.flag`: small square status mark at the end of a chapter row.
struct MDFlag: View {
    let systemImage: String
    var accent = false
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(accent ? Color.mdAccent : Color.mdText2)
            .frame(width: 22, height: 22)
    }
}

extension View {
    /// Transparent navigation bar over the title page's backdrop.
    func mdEntryNavigationBar() -> some View {
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
