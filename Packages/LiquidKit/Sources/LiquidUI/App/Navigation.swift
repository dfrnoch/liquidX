import SwiftUI
import XKit

enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case home, notifications, bookmarks, profile, search

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .notifications: "Notifications"
        case .bookmarks: "Bookmarks"
        case .profile: "Profile"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .notifications: "bell"
        case .bookmarks: "bookmark"
        case .profile: "person"
        case .search: "magnifyingglass"
        }
    }

    var selectedSymbol: String {
        self == .search ? symbol : symbol + ".fill"
    }
}

enum Route: Hashable {
    case profile(XUser)
    case user(String)
    case post(XPost)
    case postID(String)
    case search(String)
}

/// Navigation path of one section's stack.
@Observable
final class Router {
    var path: [Route] = []

    func push(_ route: Route) {
        path.append(route)
    }

    func popToRoot() {
        path.removeAll()
    }
}

/// A `NavigationStack` with LiquidX's destinations and in-app link routing.
struct RoutedStack<Root: View>: View {
    @Bindable var router: Router
    @ViewBuilder var root: Root

    var body: some View {
        NavigationStack(path: $router.path) {
            root
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
        .environment(router)
        .environment(\.openURL, OpenURLAction { url in
            if let link = AppLink(url: url) ?? AppLink(webURL: url) {
                switch link {
                case .user(let name): router.push(.user(name))
                case .search(let query): router.push(.search(query))
                case .post(let id): router.push(.postID(id))
                }
                return .handled
            }
            return .systemAction
        })
    }
}

private struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .profile(let user): ProfileView(user: user)
        case .user(let username): ProfileView(username: username)
        case .post(let post): PostDetailView(post: post)
        case .postID(let id): PostLoader(id: id)
        case .search(let query): SearchResultsView(query: query)
        }
    }
}

/// Opens a post known only by ID (deep links, x.com status links).
private struct PostLoader: View {
    let id: String

    @Environment(Session.self) private var session
    @State private var post: XPost?
    @State private var error: String?

    var body: some View {
        Group {
            if let post {
                PostDetailView(post: post)
            } else if let error {
                ContentUnavailableView("Post unavailable", systemImage: "text.bubble", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .task {
            do {
                post = try await session.service.post(id: id)
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
