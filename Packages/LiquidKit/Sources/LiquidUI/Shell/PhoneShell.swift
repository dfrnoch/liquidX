#if os(iOS)
import SwiftUI
import XKit

/// iPhone: floating Liquid Glass tab bar that minimizes while scrolling, with
/// Search as its own glass button. iPad: the same tabs adapt into a sidebar.
struct PhoneShell: View {
    @Environment(Session.self) private var session

    var body: some View {
        TabView(selection: Binding(get: { session.section }, set: { session.select($0) })) {
            Tab("Home", systemImage: "house", value: AppSection.home) {
                RoutedStack(router: session.router(for: .home)) { HomeScreen() }
            }
            Tab("Notifications", systemImage: "bell", value: AppSection.notifications) {
                RoutedStack(router: session.router(for: .notifications)) { NotificationsScreen() }
            }
            .badge(session.unreadMentions)
            Tab("Bookmarks", systemImage: "bookmark", value: AppSection.bookmarks) {
                RoutedStack(router: session.router(for: .bookmarks)) { BookmarksScreen() }
            }
            Tab("Profile", systemImage: "person", value: AppSection.profile) {
                RoutedStack(router: session.router(for: .profile)) { MyProfileScreen() }
            }
            Tab(value: AppSection.search, role: .search) {
                RoutedStack(router: session.router(for: .search)) { SearchScreen() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewStyle(.sidebarAdaptable)
    }
}
#endif
