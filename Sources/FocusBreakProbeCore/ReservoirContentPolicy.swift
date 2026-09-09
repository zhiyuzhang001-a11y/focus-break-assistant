import Foundation

public enum ReservoirContentPolicy {
    public static func accepts(_ category: ImageCategory, metadata: String) -> Bool {
        let text = metadata.lowercased()
        if ["ai-generated", "stable diffusion", "midjourney", "artificial intelligence", "paintings", "painting by", "oil on canvas", "drawings", "illustrations", "sculptures", "diagrams", "maps of", "lingerie", "bodysuit", "nude", "nudity", "erotic", "louvre", "botticelli", "titian", "raphael", "museum", "oil painting"].contains(where: text.contains) { return false }
        if category == .animals && ["nebula", "locomotive", "train station", "statue", "sculpture"].contains(where: text.contains) { return false }
        if category == .people {
            if ["bust", "herm", "statue", "sculpture", "marble", "birds", "lynx", "parrot", "gull", "rooster", "peafowl", "lizards", "portraits of animals"].contains(where: text.contains) { return false }
            return text.range(of: #"\b(men|women|woman|man|people|human|boys|girls|person|male|female)\b"#, options: .regularExpression) != nil
        }
        return true
    }
}
