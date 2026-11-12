import Foundation
import Testing
import os
import XKit
@testable import LiquidUI

@MainActor
@Suite("Feed store")
struct FeedStoreTests {
    static let author = XUser(id: "1", name: "Ada Example", username: "ada_example")

    static func page(_ ids: [String]) -> TimelinePage {
        TimelinePage(items: ids.map { XTimelineItem(XPost(id: $0, author: author, createdAt: .now, text: AttributedString($0))) }, nextCursor: "bottom")
    }

    /// A ranked feed serves posts already on screen again; refreshing adds only
    /// the new ones on top and leaves the rest where they were.
    @Test func refreshKeepsKnownPostsInPlace() async {
        let pages = OSAllocatedUnfairLock(initialState: [Self.page(["a", "b", "c"]), Self.page(["d", "c", "e"])])
        let store = FeedStore { _ in pages.withLock { $0.removeFirst() } }
        await store.loadIfNeeded()
        await store.refresh()
        #expect(store.items.map(\.id) == ["d", "e", "a", "b", "c"])
        #expect(store.unseenCount == 2)
    }

    @Test func refreshWithNothingNewChangesNothing() async {
        let pages = OSAllocatedUnfairLock(initialState: [Self.page(["a", "b"]), Self.page(["b", "a"])])
        let store = FeedStore { _ in pages.withLock { $0.removeFirst() } }
        await store.loadIfNeeded()
        await store.refresh()
        #expect(store.items.map(\.id) == ["a", "b"])
        #expect(store.unseenCount == 0)
    }
}
