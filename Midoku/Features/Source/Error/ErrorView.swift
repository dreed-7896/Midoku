//
//  ErrorView.swift
//  Midoku
//
//  Created by Skitty on 10/13/23.
//

import AidokuRunner
import SwiftUI
import Wasm3

// source error warning triangle with associated text and retry button if applicable
struct ErrorView: View {
    let error: Error
    var restart: (() async throws -> Void)?
    var retry: (() async -> Void)?

    @State private var loading = false

    var body: some View {
        MDEmpty(
            systemImage: "exclamationmark.triangle",
            title: "Couldn’t load",
            detail: Text(error.midokuDescription()),
            action: retryAction,
            tone: .error
        )
    }

    private var retryAction: MDStateAction? {
        guard let retry else { return nil }
        if let error = error as? SourceError {
            if case .unimplemented = error { return nil }
            return action(NSLocalizedString("RETRY"), retry)
        }
        if let restart, let error = error as? Wasm3Error {
            switch error {
                case .trap, .runtimeDisabled:
                    return action(NSLocalizedString("RESTART")) {
                        do {
                            try await restart()
                            await retry()
                        } catch {
                            LogManager.logger.error("Failed to restart source: \(error)")
                        }
                    }
                default:
                    return nil
            }
        }
        return nil
    }

    private func action(_ title: String, _ run: @escaping () async -> Void) -> MDStateAction {
        MDStateAction(label: title, busy: loading) {
            loading = true
            Task {
                await run()
                loading = false
            }
        }
    }
}
