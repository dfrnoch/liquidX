import SwiftUI
import XKit

@Observable
final class ProfileModel {
    enum Tab: String, CaseIterable, Identifiable {
        case posts, replies, media
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .posts: "Posts"
            case .replies: "Replies"
            case .media: "Media"
            }
        }
    }

    var user: XUser?
    let username: String
    var error: String?
    var tab: Tab = .posts
    var isUpdatingFollow = false
    private(set) var posts: FeedStore?
    private(set) var withReplies: FeedStore?

    init(user: XUser?, username: String) {
        self.user = user
        self.username = username
    }

    func load(using session: Session) async {
        if username.caseInsensitiveCompare(session.me.username) == .orderedSame {
            user = session.me
        } else {
            do {
                user = try await session.service.user(username: username)
            } catch is CancellationError {
                return
            } catch {
                if user == nil { self.error = error.localizedDescription }
            }
        }
        guard let user, posts == nil else { return }
        let service = session.service
        let id = user.id
        posts = FeedStore { page in try await service.posts(of: id, page, includeReplies: false) }
        withReplies = FeedStore { page in try await service.posts(of: id, page, includeReplies: true) }
    }

    var currentFeed: FeedStore? {
        tab == .replies ? withReplies : posts
    }

    func toggleFollow(using session: Session) async {
        guard var user, !isUpdatingFollow else { return }
        let follow = !(user.isFollowedByMe ?? false)
        isUpdatingFollow = true
        defer { isUpdatingFollow = false }
        user.isFollowedByMe = follow
        user.followers += follow ? 1 : -1
        withAnimation(.snappy) { self.user = user }
        do {
            try await session.service.setFollowing(follow, userID: user.id)
        } catch {
            user.isFollowedByMe = !follow
            user.followers += follow ? -1 : 1
            withAnimation(.snappy) { self.user = user }
            session.report(error)
        }
    }
}

struct ProfileView: View {
    @State private var model: ProfileModel
    /// Average colour of the banner (or avatar), bled into the header.
    @State private var tint: Color?
    @State private var isPastBanner = false
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme

    init(user: XUser) {
        _model = State(initialValue: ProfileModel(user: user, username: user.username))
    }

    init(username: String) {
        _model = State(initialValue: ProfileModel(user: nil, username: username))
    }

    private var bannerHeight: CGFloat { sizeClass == .compact ? 160 : 220 }

    private static func sampleTint(for user: XUser) async -> Color? {
        for url in [user.bannerURL, user.avatarURL].compactMap({ $0 }) {
            if url.scheme == "demo" { return DemoArtwork.dominantColor(seed: url.path()) }
            if let rgb = await ImagePipeline.shared.averageColor(for: url) {
                return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if let user = model.user {
                content(user)
            } else if let error = model.error {
                ContentUnavailableView("This account doesn't exist", systemImage: "person.crop.circle.badge.questionmark", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .task { await model.load(using: session) }
    }

    private func content(_ user: XUser) -> some View {
        let wash = tint.map { $0.mix(with: Theme.canvas, by: colorScheme == .dark ? 0.45 : 0.7) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ProfileBanner(user: user, height: bannerHeight)
                ProfileHeader(user: user, model: model, ringColor: wash ?? Theme.canvas)
                SegmentedPicker(selection: $model.tab, options: ProfileModel.Tab.allCases.map { ($0, $0.title) })
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .rowSeparator()

                if let feed = model.currentFeed {
                    if model.tab == .media {
                        MediaTab(store: feed)
                    } else {
                        FeedRows(store: feed, emptyTitle: "No posts yet", emptyMessage: "When \(user.handle) posts, they'll show up here.")
                            .task(id: model.tab) { await feed.loadIfNeeded() }
                    }
                }
            }
            .background(alignment: .top) {
                // The banner's colour leaks down behind the header and fades
                // into the canvas, like the Liquid Glass X concepts.
                if let wash {
                    LinearGradient(
                        stops: [
                            .init(color: wash, location: 0),
                            .init(color: wash.mix(with: Theme.canvas, by: 0.5), location: 0.55),
                            .init(color: Theme.canvas, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: bannerHeight + 560)
                    .transition(.opacity)
                }
            }
            .readableWidth()
        }
        .animation(.easeOut(duration: 0.35), value: tint)
        .ignoresSafeArea(edges: .top)
        // Keep the banner clean under the bar; blur softly once content
        // scrolls underneath it.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(!isPastBanner, for: .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > bannerHeight - 90
        } action: { _, past in
            withAnimation(.easeInOut(duration: 0.2)) { isPastBanner = past }
        }
        .task(id: user.bannerURL ?? user.avatarURL) { tint = await Self.sampleTint(for: user) }
        .refreshable {
            await model.load(using: session)
            await model.currentFeed?.refresh()
        }
        .navigationTitle(user.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ProfileTitle(user: user, overBanner: !isPastBanner)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search posts", systemImage: "magnifyingglass") {
                    session.open(.search("from:\(user.username)"))
                }
            }
        }
        #else
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Search posts", systemImage: "magnifyingglass") {
                    session.open(.search("from:\(user.username)"))
                }
            }
        }
        #endif
    }
}

/// "Name ✓ 1,204 posts" written straight over the banner (white with a soft
/// shadow), then in the regular text colour once the banner scrolls away.
private struct ProfileTitle: View {
    let user: XUser
    let overBanner: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(user.name).font(.headline).lineLimit(1)
            VerifiedBadge(verification: user.verification, size: 15)
            Text("\(Formatting.compact(user.postCount)) posts")
                .font(.subheadline.weight(.medium))
                .opacity(0.72)
                .lineLimit(1)
        }
        .foregroundStyle(overBanner ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .shadow(color: .black.opacity(overBanner ? 0.45 : 0), radius: 6, y: 1)
        .animation(.easeInOut(duration: 0.2), value: overBanner)
    }
}

/// The banner stretches when pulled down instead of revealing empty space.
private struct ProfileBanner: View {
    let user: XUser
    let height: CGFloat

    var body: some View {
        Group {
            if let url = user.bannerURL {
                RemoteImage(url, pointSize: 1_000)
            } else {
                LinearGradient(
                    colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .visualEffect { content, proxy in
            let pull = max(0, proxy.frame(in: .scrollView).minY)
            return content
                .scaleEffect(1 + pull / height, anchor: .bottom)
        }
        .accessibilityHidden(true)
    }
}

private struct ProfileHeader: View {
    let user: XUser
    let model: ProfileModel
    var ringColor: Color = Theme.canvas

    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isMe: Bool { user.id == session.me.id }
    private var avatarSize: CGFloat { sizeClass == .compact ? 88 : 128 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                Avatar(user: user, size: avatarSize)
                    .padding(4)
                    .background(ringColor, in: user.verification == .business
                        ? AnyShape(RoundedRectangle(cornerRadius: avatarSize * 0.24, style: .continuous))
                        : AnyShape(Circle()))
                    .offset(y: -avatarSize / 2)
                    .padding(.bottom, -avatarSize / 2)
                Spacer()
                if sizeClass == .compact {
                    moreButton
                } else {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            moreButton
                            secondaryButton
                            primaryButton.fixedSize()
                        }
                    }
                }
            }
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.name).font(.title2.weight(.heavy))
                    VerifiedBadge(verification: user.verification, size: 20)
                    if user.isProtected {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    }
                }
                Text(user.handle).font(.body).foregroundStyle(.secondary)
            }

            if !user.bio.characters.isEmpty {
                Text(user.bio)
                    .tint(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                count(user.followers, "Followers")
                count(user.following, "Following")
            }

            meta

            if sizeClass == .compact {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        secondaryButton
                        primaryButton
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func count(_ value: Int, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(Formatting.compact(value)).fontWeight(.bold).monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(label).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var meta: some View {
        let items = HStack(spacing: 14) {
            if let location = user.location {
                Label(location, systemImage: "mappin.and.ellipse")
            }
            if let website = user.website {
                Button { openURL(website) } label: {
                    Label(user.websiteDisplay ?? website.host() ?? website.absoluteString, systemImage: "link")
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            if let joined = user.joined {
                Label("Joined \(joined.formatted(.dateTime.month(.wide).year()))", systemImage: "calendar")
            }
        }
        ViewThatFits(in: .horizontal) {
            items.lineLimit(1)
            VStack(alignment: .leading, spacing: 6) {
                if let location = user.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
                if let website = user.website {
                    Button { openURL(website) } label: {
                        Label(user.websiteDisplay ?? website.host() ?? website.absoluteString, systemImage: "link")
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                if let joined = user.joined {
                    Label("Joined \(joined.formatted(.dateTime.month(.wide).year()))", systemImage: "calendar")
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .labelStyle(TightLabelStyle())
    }

    private var moreButton: some View {
        Menu {
            ShareLink(item: user.profileURL) { Label("Share Profile", systemImage: "square.and.arrow.up") }
            Button("Copy Link", systemImage: "link") { Pasteboard.copy(user.profileURL.absoluteString) }
            Button("Open on x.com", systemImage: "safari") { openURL(user.profileURL) }
            if isMe {
                Divider()
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    session.signOut()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .menuIndicator(.hidden)
        .fixedSize()
        .neutralGlassTint()
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private var secondaryButton: some View {
        if isMe {
            SettingsLinkButton()
        } else {
            Button {
                openURL(URL(string: "https://x.com/messages/compose?recipient_id=\(user.id)")!)
            } label: {
                Image(systemName: "envelope")
                    .font(.body.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .neutralGlassButton(circle: true)
            .accessibilityLabel("Message")
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isMe {
            Button {
                openURL(URL(string: "https://x.com/settings/profile")!)
            } label: {
                Text("Edit profile").font(.headline).foregroundStyle(.primary).frame(maxWidth: .infinity)
            }
            .neutralGlassButton(circle: false)
        } else if user.isFollowedByMe == true {
            Button {
                Task { await model.toggleFollow(using: session) }
            } label: {
                Text("Following").font(.headline).foregroundStyle(.primary).frame(maxWidth: .infinity)
            }
            .neutralGlassButton(circle: false)
            .disabled(model.isUpdatingFollow)
        } else {
            Button {
                Task { await model.toggleFollow(using: session) }
            } label: {
                Text("Follow").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(model.isUpdatingFollow)
        }
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// Opens Settings: a sheet on iOS, the Settings window on macOS.
struct SettingsLinkButton: View {
    @Environment(Session.self) private var session

    var body: some View {
        #if os(macOS)
        SettingsLink {
            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
        }
        .neutralGlassButton(circle: true)
        .accessibilityLabel("Settings")
        #else
        Button {
            session.isShowingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
        }
        .neutralGlassButton(circle: true)
        .accessibilityLabel("Settings")
        #endif
    }
}

/// Grid of every photo and video from the account's recent posts.
private struct MediaTab: View {
    let store: FeedStore

    @Environment(Session.self) private var session

    private var tiles: [(XMedia, XPost)] {
        store.items.flatMap { item in item.post.media.map { ($0, item.post) } }
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(tiles, id: \.0.id) { media, post in
                RemoteImage(media.imageURL(.small), pointSize: 240)
                    .aspectRatio(1, contentMode: .fill)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        session.showMedia(post.media, index: post.media.firstIndex(of: media) ?? 0, post: post)
                    }
            }
        }
        .task { await store.loadIfNeeded() }
        .overlay {
            if tiles.isEmpty, store.phase == .loaded {
                Text("No media yet").foregroundStyle(.secondary).padding(40)
            }
        }
        .frame(minHeight: 120, alignment: .top)
    }
}
