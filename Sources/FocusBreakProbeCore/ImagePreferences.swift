import Foundation

public enum ImageCategory: String, Codable, CaseIterable, Sendable {
    case nature, space, animals, city, people, cartoon
    public var title: String {
        switch self {
        case .nature: "自然风景"
        case .space: "宇宙星空"
        case .animals: "动物"
        case .city: "城市"
        case .people: "人物"
        case .cartoon: "卡通插画"
        }
    }
    public var symbol: String {
        switch self {
        case .nature: "mountain.2"
        case .space: "moon.stars"
        case .animals: "pawprint"
        case .city: "building.2"
        case .people: "person.2"
        case .cartoon: "paintpalette"
        }
    }
    public var onlineQuery: String? {
        switch self {
        case .nature: "landscape nature"
        case .animals: "wildlife animals"
        case .city: "city architecture"
        case .people: "people daily life"
        case .space, .cartoon: nil
        }
    }
}

public struct ImagePreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var categories: [ImageCategory] {
        get {
            let saved = (defaults.stringArray(forKey: "imageCategories") ?? []).compactMap(ImageCategory.init(rawValue:))
            return saved.isEmpty ? [.nature] : ImageCategory.allCases.filter { saved.contains($0) }
        }
        nonmutating set { defaults.set((newValue.isEmpty ? [.nature] : newValue).map(\.rawValue), forKey: "imageCategories") }
    }
    public var active: Bool {
        get { defaults.bool(forKey: "categoryLibraryActive") }
        nonmutating set { defaults.set(newValue, forKey: "categoryLibraryActive") }
    }
    public var askDaily: Bool {
        get { defaults.object(forKey: "askImageCategoryDaily") as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: "askImageCategoryDaily") }
    }
    public var peopleStyle: String {
        get { defaults.string(forKey: "peopleImageStyle") ?? "生活纪实" }
        nonmutating set { defaults.set(newValue, forKey: "peopleImageStyle") }
    }
    public func shouldAsk(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard askDaily else { return false }
        guard let last = defaults.object(forKey: "imageChoiceLastPresented") as? Date else { return true }
        return !calendar.isDate(last, inSameDayAs: date)
    }
    public func markPresented(at date: Date = Date()) { defaults.set(date, forKey: "imageChoiceLastPresented") }
}
