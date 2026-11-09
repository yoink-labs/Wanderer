import Foundation

/// Curated, license-friendly destination photography.
/// Images are loaded from the Unsplash CDN at runtime; the app never ships
/// copyrighted binaries. A trip's `cover_url` always wins when present.
enum ImageCatalog {
    static func cover(for destination: String) -> URL? {
        let key = destination.lowercased()
        let id: String

        if key.contains("kyoto") || key.contains("japan") {
            id = "photo-1493976040374-85c8e12f0c0e"
        } else if key.contains("lisbon") || key.contains("portugal") {
            id = "photo-1555881400-74d7acaacd8b"
        } else if key.contains("reykjav") || key.contains("iceland") {
            id = "photo-1504893524553-b855bce32c67"
        } else if key.contains("barcelona") || key.contains("spain") {
            id = "photo-1583422409516-2895a77efded"
        } else if key.contains("paris") || key.contains("france") {
            id = "photo-1502602898657-3e91760cbb34"
        } else if key.contains("rome") || key.contains("italy") {
            id = "photo-1552832230-c0197dd311b5"
        } else if key.contains("bali") || key.contains("indonesia") {
            id = "photo-1537996194471-e657df975ab4"
        } else if key.contains("new york") || key.contains("nyc") {
            id = "photo-1496442226666-8d4d0e62e6e9"
        } else if key.contains("rio") || key.contains("brazil") || key.contains("brasil") {
            id = "photo-1483729558449-99ef09a8c325"
        } else if key.contains("buenos aires") || key.contains("argentina") {
            id = "photo-1589909202802-8f4aadce1849"
        } else if key.contains("beach") || key.contains("island") {
            id = "photo-1507525428034-b723cf961d3e"
        } else if key.contains("mountain") || key.contains("alps") {
            id = "photo-1464822759023-fed622ff2c3b"
        } else {
            id = "photo-1488646953014-85cb44e25828"
        }

        return URL(string: "https://images.unsplash.com/\(id)?auto=format&fit=crop&w=1200&q=80")
    }

    static func placePhoto(for name: String) -> URL? {
        cover(for: name)
    }
}
