import SwiftUI
import UIKit

/// Round profile photo with an initials fallback while loading or when no
/// avatar has been uploaded.
struct ProfileAvatarView: View {
    let avatarURL: String?
    let initials: String
    var size: CGFloat = 64

    private var url: URL? {
        guard let avatarURL,
              !avatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(string: avatarURL)
    }

    var body: some View {
        ZStack {
            Circle().fill(WandererTheme.dust)

            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        initialsLabel
                    }
                }
            } else {
                initialsLabel
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initialsLabel: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(WandererTheme.ink)
    }
}

enum AvatarImageEncoder {
    /// Decodes picker data (HEIC, PNG, JPEG), shrinks it to a square-ish avatar
    /// no larger than `maxDimension`, and re-encodes as JPEG for the
    /// `avatars` bucket. Returns nil when the data is not an image.
    static func jpegData(from data: Data, maxDimension: CGFloat = 512, quality: CGFloat = 0.82) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
