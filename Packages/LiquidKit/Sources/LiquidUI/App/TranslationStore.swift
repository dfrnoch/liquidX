import SwiftUI
import Translation
import XKit

/// One post's translation. Kept for the session, so a row scrolled away and
/// back still shows it.
@Observable
final class PostTranslation {
    enum Phase: Equatable {
        case original
        case translating
        case translated
    }

    var phase: Phase = .original
    /// The translation so far; grows while X streams it in.
    var text: AttributedString?
    var isStreaming = false
    /// Set to have the post's text view translate it on the device.
    var deviceRequest: TranslationSession.Configuration?
}

/// Translates posts into the reader's language, like X's "Show translation":
/// through the connection when it can (Grok, on x.com sessions), on the
/// device with Apple's Translation otherwise or when that fails.
final class TranslationStore {
    let reader: Locale.Language
    private let service: any XService
    private var states: [String: PostTranslation] = [:]
    weak var session: Session?

    init(service: any XService, reader: Locale.Language = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")) {
        self.service = service
        self.reader = reader
    }

    func offers(_ post: XPost) -> Bool {
        post.isTranslatable(for: reader)
    }

    func state(for post: XPost) -> PostTranslation {
        if let state = states[post.id] { return state }
        let state = PostTranslation()
        states[post.id] = state
        return state
    }

    /// Translates the post, or switches between its translation and the original.
    func toggle(_ post: XPost) {
        let state = state(for: post)
        switch state.phase {
        case .translating:
            break
        case .translated:
            state.phase = .original
        case .original where state.text != nil:
            state.phase = .translated
        case .original:
            translate(post, state)
        }
    }

    private func translate(_ post: XPost, _ state: PostTranslation) {
        state.phase = .translating
        let onDevice = TranslationSession.Configuration(source: post.spokenLanguage, target: reader)
        guard let stream = service.translation(of: post, into: reader.languageCode?.identifier ?? "en") else {
            state.deviceRequest = onDevice
            return
        }
        Task {
            var failed = false
            do {
                for try await text in stream {
                    // The original stays up if it was asked for mid-stream.
                    if state.text == nil { state.phase = .translated }
                    state.isStreaming = true
                    state.text = text
                }
            } catch {
                failed = true
            }
            state.isStreaming = false
            if state.text == nil {
                // x.com's translation is unofficial and may break; the device
                // can still translate.
                state.deviceRequest = onDevice
            } else if failed {
                session?.show(Toast(message: "The translation stopped partway.", symbol: "exclamationmark.triangle.fill", isError: true))
            }
        }
    }

    /// The result of the text view's `translationTask`, which may have asked
    /// to download the languages first.
    func finishOnDevice(_ post: XPost, with result: Result<String, any Error>) {
        let state = state(for: post)
        switch result {
        case .success(let translated):
            state.text = RichText.translation(translated, of: post.text)
            state.phase = .translated
        case .failure(is CancellationError):
            // The row scrolled away; the request stays for when it's back.
            return
        case .failure(let error):
            state.phase = .original
            session?.report(error)
        }
        state.deviceRequest = nil
    }
}
