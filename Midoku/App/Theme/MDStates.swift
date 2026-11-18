//
//  MDStates.swift
//  Midoku
//
//  Midoku Web's shared states (src/components/Status.tsx, `.state` / `.loading` / `.banner-line`):
//  empty results, caught up, errors, loading placeholders and slim banners. One look everywhere.
//

import SwiftUI
import UIKit

enum MDTone {
    case neutral, done, error

    var iconBackground: Color {
        switch self {
            case .neutral: .mdS3
            case .done: Color(uiColor: MDColor.mint).opacity(0.14)
            case .error: Color(uiColor: MDColor.amber).opacity(0.14)
        }
    }

    var iconColor: Color {
        switch self {
            case .neutral: .mdText2
            case .done: Color(uiColor: MDColor.mint)
            case .error: Color(uiColor: MDColor.amber)
        }
    }
}

/// Line-style symbol, as the web's Hugeicons are outlines.
func mdLineSymbol(_ name: String) -> String {
    let stripped = name.replacingOccurrences(of: ".fill", with: "")
    return UIImage(systemName: stripped) != nil ? stripped : name
}

/// `.btn.btn--ghost.btn--sm`: transparent, hairline border.
struct MDGhostButtonStyle: ButtonStyle {
    var small = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mdSystem(size: small ? 13 : 14, weight: .semibold))
            .foregroundStyle(Color.mdText)
            .padding(.horizontal, small ? 12 : 16)
            .frame(height: small ? 36 : 44)
            .overlay(Rectangle().strokeBorder(Color.mdLine2, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct MDStateAction {
    let label: String
    var busy = false
    let action: () -> Void
}

/// `<Empty>`: dashed card with a square icon tile, bold title, muted detail and an optional ghost button.
struct MDEmpty: View {
    var systemImage = "info.circle"
    let title: String
    var detail: Text?
    var action: MDStateAction?
    var tone: MDTone = .neutral
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 12 : 14) {
            Image(systemName: mdLineSymbol(systemImage))
                .font(.system(size: compact ? 16 : 19, weight: .medium))
                .foregroundStyle(tone.iconColor)
                .frame(width: compact ? 34 : 44, height: compact ? 34 : 44)
                .background(tone.iconBackground)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.mdSystem(size: 15, weight: .bold))
                    .foregroundStyle(Color.mdText)
                if let detail {
                    detail
                        .font(.mdSystem(size: 13))
                        .foregroundStyle(Color.mdText3)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            if let action {
                if action.busy {
                    MDSpinner().frame(width: 36, height: 36)
                } else {
                    Button(action.label, action: action.action).buttonStyle(MDGhostButtonStyle())
                }
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 12 : 18)
        .background(Color.mdS1)
        .overlay(Rectangle().strokeBorder(Color.mdLine2, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// An `MDEmpty` placed like a web page section: 16pt gutters, at the top of the space it is given.
struct MDEmptyPage: View {
    var systemImage = "info.circle"
    let title: String
    var detail: Text?
    var action: MDStateAction?
    var tone: MDTone = .neutral

    var body: some View {
        VStack(spacing: 0) {
            MDEmpty(systemImage: systemImage, title: title, detail: detail, action: action, tone: tone)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// `.spinner`: 12pt square ring with an accent arc.
struct MDSpinner: View {
    var size: CGFloat = 12
    @State private var spinning = false

    var body: some View {
        ZStack {
            Rectangle().strokeBorder(Color.mdS3, lineWidth: 2)
            Rectangle()
                .trim(from: 0, to: 0.25)
                .stroke(Color.mdAccent, lineWidth: 2)
                .padding(1)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
        .onAppear { spinning = true }
        .accessibilityHidden(true)
    }
}

/// `.loading__bar`: 28×3 track with an accent segment sliding back and forth.
struct MDLoadingBar: View {
    @State private var slid = false

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.mdS3)
            Rectangle().fill(Color.mdAccent)
                .frame(width: 28 * 0.4)
                .offset(x: slid ? 28 * 0.4 * 1.5 : 0)
        }
        .frame(width: 28, height: 3)
        .clipped()
        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: slid)
        .onAppear { slid = true }
    }
}

/// `.skeleton`: flat block pulsing between s2 and s3.
struct MDSkeleton: View {
    @State private var lit = false

    var body: some View {
        Rectangle()
            .fill(lit ? Color.mdS3 : Color.mdS2)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: lit)
            .onAppear { lit = true }
    }
}

/// `<Loading>`: mono label with a sliding bar, over placeholder shapes.
struct MDLoading: View {
    enum Shape { case grid, rail, rows, page }

    let label: String
    var shape: Shape = .grid
    var count: Int?

    private var n: Int {
        count ?? { switch shape { case .grid: 6; case .rail: 3; case .rows: 4; case .page: 1 } }()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MDLoadingBar()
                Text(label)
                    .font(.mdMono(11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.mdText3)
                    .lineLimit(1)
            }
            shapes.accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: shape == .page ? .center : .leading)
        .padding(.vertical, shape == .page ? 40 : 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var shapes: some View {
        switch shape {
            case .grid:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(0..<n, id: \.self) { _ in MDSkeleton().aspectRatio(3 / 4, contentMode: .fit) }
                }
            case .rail:
                HStack(spacing: 10) {
                    ForEach(0..<n, id: \.self) { _ in MDSkeleton().frame(width: 118, height: 157) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            case .rows:
                VStack(spacing: 10) {
                    ForEach(0..<n, id: \.self) { _ in MDSkeleton().frame(height: 58) }
                }
            case .page:
                EmptyView()
        }
    }
}

/// `MDLoading` placed like a web page section.
struct MDLoadingPage: View {
    let label: String
    var shape: MDLoading.Shape = .grid
    var count: Int?

    var body: some View {
        MDLoading(label: label, shape: shape, count: count)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// `<Banner>`: slim line with a 3pt left rule; busy shows the spinner.
struct MDBanner<Content: View>: View {
    enum Tone { case neutral, busy, done, error }

    var systemImage = "info.circle"
    var tone: Tone = .neutral
    @ViewBuilder var content: Content

    private var rule: Color {
        switch tone {
            case .neutral: .mdLine2
            case .busy: .mdAccent
            case .done: Color(uiColor: MDColor.mint)
            case .error: Color(uiColor: MDColor.amber)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if tone == .busy {
                MDSpinner()
            } else {
                Image(systemName: mdLineSymbol(systemImage)).font(.system(size: 13, weight: .medium))
            }
            content.font(.mdSystem(size: 13))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.mdText2)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.mdS1)
        .overlay(alignment: .leading) { Rectangle().fill(rule).frame(width: 3) }
    }
}

// MARK: - UIKit

/// UIKit `<Empty>` card for view controllers that are not SwiftUI.
final class MDStateCardView: UIView {
    var onAction: (() -> Void)?

    private let iconTile = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let border = CAShapeLayer()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private(set) lazy var actionButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = MDColor.text
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = MDFont.ui(13, .semibold) ?? .systemFont(ofSize: 13, weight: .semibold)
            return attributes
        }
        config.background.strokeColor = MDColor.line2
        config.background.strokeWidth = 1
        config.background.cornerRadius = 0
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        backgroundColor = MDColor.s1

        border.fillColor = nil
        border.strokeColor = MDColor.line2.cgColor
        border.lineWidth = 1
        border.lineDashPattern = [4, 3]
        layer.addSublayer(border)

        iconTile.backgroundColor = MDColor.s3
        iconView.contentMode = .center
        iconView.tintColor = MDColor.text2
        iconTile.addSubview(iconView)

        titleLabel.font = MDFont.ui(15, .bold) ?? .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = MDColor.text
        titleLabel.numberOfLines = 0
        detailLabel.font = MDFont.ui(13) ?? .systemFont(ofSize: 13)
        detailLabel.textColor = MDColor.text3
        detailLabel.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 3

        spinner.color = MDColor.accent
        spinner.hidesWhenStopped = true

        actionButton.isHidden = true
        let row = UIStackView(arrangedSubviews: [iconTile, text, actionButton, spinner])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        addSubview(row)

        [iconTile, iconView, row].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            iconTile.widthAnchor.constraint(equalToConstant: 44),
            iconTile.heightAnchor.constraint(equalToConstant: 44),
            iconView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
        set(systemImage: "info.circle", title: "", detail: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.frame = bounds
        border.path = UIBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).cgPath
    }

    func set(systemImage: String, title: String, detail: String?, tone: MDTone = .neutral) {
        let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        iconView.image = UIImage(systemName: mdLineSymbol(systemImage), withConfiguration: config)
        switch tone {
            case .neutral:
                iconTile.backgroundColor = MDColor.s3
                iconView.tintColor = MDColor.text2
            case .done:
                iconTile.backgroundColor = MDColor.mint.withAlphaComponent(0.14)
                iconView.tintColor = MDColor.mint
            case .error:
                iconTile.backgroundColor = MDColor.amber.withAlphaComponent(0.14)
                iconView.tintColor = MDColor.amber
        }
        titleLabel.text = title
        detailLabel.text = detail
        detailLabel.isHidden = detail?.isEmpty ?? true
    }

    func setAction(_ title: String?) {
        if let title {
            actionButton.configuration?.title = title
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }
    }

    func setBusy(_ busy: Bool) {
        if busy {
            actionButton.alpha = 0
            actionButton.isHidden = true
            spinner.startAnimating()
        } else {
            actionButton.alpha = 1
            spinner.stopAnimating()
        }
    }

    @objc private func actionPressed() {
        onAction?()
    }
}
