import SwiftUI
import XKit

struct HomeScreen: View {
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var session = session
        FeedScreen(
            store: session.home,
            emptyTitle: "Welcome to your timeline",
            emptySymbol: "house",
            emptyMessage: "Posts from accounts you follow appear here.",
            scrollToTopTrigger: session.scrollToTopTicks[.home, default: 0]
        )
            .id(session.homeFilter)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await session.home.refreshIfStale(after: session.autoRefreshInterval) }
            }
            .navigationTitle("Home")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) { ComposeButton() }
            #endif
            .toolbar {
                if session.service.homeFeeds.count > 1 {
                    ToolbarItem(placement: .principal) {
                        HomeFeedPicker(selection: $session.homeFilter.feed, feeds: session.service.homeFeeds)
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button { session.section = .profile } label: {
                        Avatar(user: session.me, size: 32)
                    }
                    .accessibilityLabel("Your profile")
                }
                .sharedBackgroundVisibility(.hidden)
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle("Show Replies", systemImage: "arrowshape.turn.up.left", isOn: Binding(
                            get: { !session.homeFilter.hideReplies },
                            set: { session.homeFilter.hideReplies = !$0 }
                        ))
                        Toggle("Show Reposts", systemImage: "arrow.2.squarepath", isOn: Binding(
                            get: { !session.homeFilter.hideReposts },
                            set: { session.homeFilter.hideReposts = !$0 }
                        ))
                    } label: {
                        Label("Filter", systemImage: !session.homeFilter.hideReplies && !session.homeFilter.hideReposts
                              ? "line.3.horizontal.decrease"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
    }
}

/// "For you | Following", as on X; only offered when the connection has both.
private struct HomeFeedPicker: View {
    @Binding var selection: HomeFeed
    let feeds: [HomeFeed]

    var body: some View {
        Picker("Feed", selection: $selection) {
            ForEach(feeds, id: \.self) { feed in
                Text(feed == .forYou ? "For you" : "Following").tag(feed)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// X's floating compose button, as a tinted glass circle.
struct ComposeButton: View {
    @Environment(Session.self) private var session

    var body: some View {
        Button { session.compose() } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.accent).interactive(), in: .circle)
        .padding(.trailing, 20)
        .padding(.bottom, 16)
        .accessibilityLabel("New post")
        .keyboardShortcut("n", modifiers: .command)
    }
}

struct NotificationsScreen: View {
    @Environment(Session.self) private var session

    var body: some View {
        FeedScreen(
            store: session.mentions,
            emptyTitle: "No mentions yet",
            emptySymbol: "bell",
            emptyMessage: "When someone mentions you, you'll find it here.",
            scrollToTopTrigger: session.scrollToTopTicks[.notifications, default: 0]
        )
            .navigationTitle("Notifications")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear { session.markMentionsSeen() }
    }
}

struct BookmarksScreen: View {
    @Environment(Session.self) private var session

    var body: some View {
        FeedScreen(
            store: session.bookmarks,
            emptyTitle: "Save posts for later",
            emptySymbol: "bookmark",
            emptyMessage: "Bookmark posts to easily find them again in the future.",
            scrollToTopTrigger: session.scrollToTopTicks[.bookmarks, default: 0]
        )
            .navigationTitle("Bookmarks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await session.bookmarks.refresh() }
    }
}

struct MyProfileScreen: View {
    @Environment(Session.self) private var session

    var body: some View {
        ProfileView(user: session.me)
            .id(session.me.id)
    }
}
