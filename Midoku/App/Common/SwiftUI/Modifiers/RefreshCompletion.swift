import SwiftUI
import SwiftUIIntrospect
import UIKit

@MainActor
private final class MCRefreshControl {
    weak var scrollView: UIScrollView?
    func finish() { scrollView?.refreshControl?.endRefreshing() }
}

private struct MCRefreshCompletion: ViewModifier {
    let action: @MainActor () async -> Void
    @State private var control = MCRefreshControl()

    func body(content: Content) -> some View {
        content
            .refreshable {
                let activeControl = control.scrollView?.refreshControl
                defer { activeControl?.endRefreshing(); control.finish() }
                await action()
            }
            .introspect(.scrollView, on: .iOS(.v18, .v26, .v27)) { scroll in
                control.scrollView = scroll
            }
    }
}

extension View {
    func mcRefreshable(action: @escaping @MainActor () async -> Void) -> some View {
        modifier(MCRefreshCompletion(action: action))
    }
}
