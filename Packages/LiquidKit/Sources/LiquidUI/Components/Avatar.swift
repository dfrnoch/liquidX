import SwiftUI
import XKit

/// Round profile picture; organizations (gold check) get X's rounded square.
struct Avatar: View {
    let user: XUser
    var size: CGFloat = 44

    private var shape: AnyShape {
        user.verification == .business
            ? AnyShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            : AnyShape(Circle())
    }

    var body: some View {
        Group {
            if let url = user.avatarURL, url.scheme != "demo" {
                RemoteImage(url, pointSize: size)
            } else {
                Initials(name: user.name, seed: user.username, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

private struct Initials: View {
    let name: String
    let seed: String
    let size: CGFloat

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        let hue = Double(stableHash(seed) % 360) / 360
        LinearGradient(
            colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95), Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

struct VerifiedBadge: View {
    let verification: XUser.Verification
    var size: CGFloat = 15

    var body: some View {
        if verification != .none {
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, color)
                .accessibilityLabel(label)
        }
    }

    private var color: Color {
        switch verification {
        case .business: Theme.gold
        case .government: .gray
        default: Theme.accent
        }
    }

    private var label: Text {
        switch verification {
        case .business: Text("Verified organization")
        case .government: Text("Government account")
        default: Text("Verified")
        }
    }
}
