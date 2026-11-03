#if os(macOS)
import SwiftUI
import XKit

/// Mac layout from the concept: a floating glass rail, the timeline column and,
/// when the window is wide enough, a "What's happening" column with search.
struct MacShell: View {
    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette
    /// The trends column only appears when the window can afford it.
    @State private var showsSidebar = true

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            MacRail()
            column
                .frame(minWidth: 520, idealWidth: 640, maxWidth: 680)
            if showsSidebar {
                TrendsColumn()
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background {
            if palette.isTranslucent {
                WindowGlass().ignoresSafeArea()
            } else {
                palette.window.ignoresSafeArea()
            }
        }
        .animation(.smooth(duration: 0.3), value: palette)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 1_080 } action: { wide in
            withAnimation(.snappy) { showsSidebar = wide }
        }
        // No toolbar backdrop: the glass toolbar items float over the canvas,
        // so no strip appears above the trends column.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: 640, minHeight: 560)
    }

    /// One stack per section; switching keeps each section's path.
    private var column: some View {
        RoutedStack(router: session.router(for: session.section)) {
            switch session.section {
            case .home: HomeScreen()
            case .notifications: NotificationsScreen()
            case .bookmarks: BookmarksScreen()
            case .profile: MyProfileScreen()
            case .search: SearchScreen()
            }
        }
        .id(session.section)
        .background(palette.column)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .padding(.vertical, 12)
    }
}

private struct MacRail: View {
    @Environment(Session.self) private var session
    @Namespace private var selection

    private let sections: [AppSection] = [.home, .notifications, .bookmarks, .search]

    var body: some View {
        VStack(spacing: 18) {
            Button { session.compose() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title2.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Theme.accent.opacity(0.85)).interactive(), in: .circle)
            .foregroundStyle(.white)
            .help("New Post (⌘N)")
            .accessibilityLabel("New post")

            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 6) {
                    ForEach(sections) { section in
                        RailButton(section: section, isSelected: session.section == section, badge: section == .notifications ? session.unreadMentions : 0, namespace: selection) {
                            withAnimation(.snappy) { session.select(section) }
                        }
                    }
                }
                .padding(6)
                .glassEffect(.regular, in: .capsule)
            }

            Spacer()

            Button {
                withAnimation(.snappy) { session.select(.profile) }
            } label: {
                Avatar(user: session.me, size: 44)
                    .padding(4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .overlay(Circle().strokeBorder(session.section == .profile ? Theme.accent : .clear, lineWidth: 2))
            .help("Profile")
            .accessibilityLabel("Profile")
        }
        .padding(.vertical, 16)
        .frame(width: 72)
    }
}

private struct RailButton: View {
    let section: AppSection
    let isSelected: Bool
    let badge: Int
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? section.selectedSymbol : section.symbol)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                .frame(width: 48, height: 48)
                .background {
                    if isSelected {
                        Circle().fill(.primary.opacity(0.12))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    } else if isHovering {
                        Circle().fill(.primary.opacity(0.06))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.accent, in: Capsule())
                            .offset(x: 2, y: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .onHover { isHovering = $0 }
        .help(Text(section.title))
        .accessibilityLabel(Text(section.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Right column: search field, trends and an about card.
private struct TrendsColumn: View {
    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette
    @State private var query = ""

    /// Trends exist for the official API (when the app has access) and the demo.
    /// Hidden on the Search screen, which lists the trends itself.
    private var showsTrendsCard: Bool {
        session.section != .search && (!session.trends.isEmpty || session.service.connection == .officialAPI)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // The Search screen has its own field; never show two.
                if session.section != .search {
                    MacSearchField(text: $query, onSubmit: submit)
                        .transition(.opacity)
                }

                if showsTrendsCard {
                card {
                    HStack {
                        Text("What's happening").font(.title2.weight(.heavy))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                    if session.trends.isEmpty {
                        Text("Personalized trends appear here when your X developer app has access to them.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    } else {
                        ForEach(session.trends) { trend in
                            Button {
                                session.submitSearch(trend.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let category = trend.category {
                                        Text(category).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Text(trend.name).font(.headline)
                                    if let count = trend.postCount {
                                        Text("\(Formatting.compact(count)) posts").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 8)
                    }
                }
                }

                if session.service.isDemo {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("You're exploring the demo", systemImage: "sparkles").font(.headline)
                            Text("Everything here is fictional and works offline. Sign in with your X developer app to see your real timeline.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Sign In with X") { session.signOut() }
                                .buttonStyle(.glassProminent)
                                .tint(Theme.accent)
                                .padding(.top, 4)
                        }
                        .padding(16)
                    }
                }

                Text("LiquidX is open source and not affiliated with X Corp.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectHidden(true, for: .top)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    private func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.submitSearch(text)
        query = ""
    }
}
#endif
