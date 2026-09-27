import SwiftUI

struct MCFullscreenCoverView: View {
    let entry: MCPersonalEntry
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let zoom = min(5, max(1, scale * magnification))
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                MCEntryCover(entry: entry, contentMode: .fit)
                    .frame(width: geometry.size.width * zoom, height: geometry.size.height * zoom)
            }
            .scrollDisabled(zoom <= 1)
            .simultaneousGesture(MagnifyGesture()
                .updating($magnification) { value, state, _ in state = value.magnification }
                .onEnded { scale = min(5, max(1, scale * $0.magnification)) })
            .onTapGesture(count: 2) { withAnimation(.snappy) { scale = scale > 1 ? 1 : 2 } }
        }
        .background(.black)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.black.opacity(0.65), in: Circle())
            }.padding().accessibilityLabel("Close cover")
        }
        .background { Color.black.ignoresSafeArea() }
        .statusBarHidden()
    }
}
