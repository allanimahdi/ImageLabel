import Foundation

/// Coarse top-level folders for Auto-Group (few buckets, not deep Vision taxonomy).
enum MainCategory: String, CaseIterable, Identifiable {
    case animals = "Animals"
    case people = "People"
    case nature = "Nature"
    case food = "Food"
    case vehicles = "Vehicles"
    case buildings = "Buildings"
    case sports = "Sports"
    case technology = "Technology"
    case art = "Art"
    case other = "Other"

    var id: String { rawValue }

    /// Folder name under the selected pictures directory.
    var folderName: String { rawValue }
}

struct CategoryAssignment: Equatable {
    let category: MainCategory
    /// Vision label that most strongly drove the assignment (for preview).
    let matchedLabel: String
}

/// Maps fine-grained Vision / Apple labels into a small curated set of main categories.
enum MainCategoryMapper {
    /// Keyword → category. First matching rule wins per label (rules are ordered specific → broad).
    private static let rules: [(category: MainCategory, keywords: [String])] = [
        (.animals, [
            "dog", "cat", "bird", "horse", "fish", "pet", "animal", "wildlife", "mammal",
            "puppy", "kitten", "retriever", "terrier", "spaniel", "poodle", "breed",
            "insect", "butterfly", "bee", "spider", "elephant", "lion", "tiger", "bear",
            "deer", "cow", "cattle", "sheep", "goat", "pig", "chicken", "duck", "goose",
            "rabbit", "hamster", "reptile", "snake", "lizard", "turtle", "frog", "whale",
            "dolphin", "shark", "penguin", "owl", "eagle", "hawk", "parrot", "canine", "feline"
        ]),
        (.people, [
            "person", "people", "human", "man", "woman", "boy", "girl", "child", "baby",
            "face", "portrait", "crowd", "selfie", "bride", "groom", "family", "skin",
            "beard", "hair", "smile", "pedestrian"
        ]),
        (.food, [
            "food", "fruit", "vegetable", "meal", "dish", "cuisine", "dessert", "drink",
            "coffee", "tea", "wine", "beer", "pizza", "burger", "sandwich", "pasta", "rice",
            "bread", "cake", "cookie", "ice cream", "salad", "soup", "meat", "seafood",
            "sushi", "breakfast", "dinner", "lunch", "snack", "chocolate", "cheese"
        ]),
        (.vehicles, [
            "car", "truck", "vehicle", "automobile", "bike", "bicycle", "motorcycle",
            "bus", "train", "airplane", "aircraft", "boat", "ship", "van", "scooter",
            "helicopter", "taxi", "jeep", "suv", "wheel", "tire", "locomotive"
        ]),
        (.buildings, [
            "building", "house", "home", "architecture", "bridge", "tower", "skyscraper",
            "church", "cathedral", "castle", "apartment", "office", "store", "shop",
            "museum", "stadium", "arena", "hotel", "school", "hospital", "door", "window",
            "roof", "facade", "interior", "room", "kitchen", "bedroom", "bathroom", "furniture"
        ]),
        (.sports, [
            "sport", "athlete", "soccer", "football", "basketball", "baseball", "tennis",
            "golf", "hockey", "cricket", "rugby", "volleyball", "skating", "skiing",
            "surf", "swim", "running", "marathon", "gym", "workout", "yoga", "ball",
            "racket", "bat", "helmet"
        ]),
        (.technology, [
            "computer", "laptop", "phone", "smartphone", "tablet", "electronics", "screen",
            "monitor", "keyboard", "mouse", "camera", "gadget", "robot", "drone",
            "headphones", "television", "tv", "console", "server", "circuit", "chip"
        ]),
        (.art, [
            "art", "painting", "drawing", "sculpture", "statue", "graffiti", "mural",
            "illustration", "sketch", "canvas", "gallery", "poster"
        ]),
        (.nature, [
            "tree", "flower", "plant", "forest", "mountain", "hill", "sky", "cloud",
            "beach", "ocean", "sea", "lake", "river", "waterfall", "landscape", "outdoor",
            "nature", "grass", "leaf", "leaves", "sunset", "sunrise", "snow", "desert",
            "canyon", "valley", "field", "garden", "park", "rock", "stone", "water",
            "flora", "vegetation", "wilderness"
        ])
    ]

    /// Assigns one main category using all labels: sum confidence per category; ties → higher single label.
    static func assign(labels: [VisionLabel]) -> CategoryAssignment? {
        guard !labels.isEmpty else { return nil }

        struct Acc {
            var total: Double = 0
            var bestLabel: String = ""
            var bestScore: Double = -1
        }
        var scores: [MainCategory: Acc] = [:]

        for label in labels {
            guard let category = category(forLabel: label.description) else { continue }
            var acc = scores[category] ?? Acc()
            acc.total += label.score
            if label.score > acc.bestScore {
                acc.bestScore = label.score
                acc.bestLabel = label.description
            }
            scores[category] = acc
        }

        if let winner = scores.max(by: { lhs, rhs in
            if lhs.value.total != rhs.value.total {
                return lhs.value.total < rhs.value.total
            }
            return lhs.value.bestScore < rhs.value.bestScore
        }) {
            return CategoryAssignment(category: winner.key, matchedLabel: winner.value.bestLabel)
        }

        // No keyword hit — still put the image somewhere coarse.
        let top = labels.max(by: { $0.score < $1.score })!
        return CategoryAssignment(category: .other, matchedLabel: top.description)
    }

    static func category(forLabel raw: String) -> MainCategory? {
        let text = raw.lowercased()
        for rule in rules {
            for keyword in rule.keywords {
                if text == keyword || text.contains(keyword) {
                    return rule.category
                }
            }
        }
        return nil
    }
}
