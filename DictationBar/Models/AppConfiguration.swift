import Foundation

struct AppConfiguration: Codable, Equatable {
    var microphoneID: String?
    var folderBookmark: Data?
    var preferBluetooth: Bool?
    var browserSuggestions: Bool?
    var shortcut: DictationShortcut?

    init(microphoneID: String? = nil, folderBookmark: Data? = nil) {
        self.microphoneID = microphoneID
        self.folderBookmark = folderBookmark
    }
}

enum RuntimeProfile: Equatable {
    case production
    case testing

    static func resolve(environment: [String: String]) -> Self {
        environment["DICTATIONBAR_RUNTIME"] == "testing" ? .testing : .production
    }
}

/// Native constructors and test constructors are separate, so a hosted test
/// cannot accidentally create or activate an adapter with system side effects.
enum RuntimeFactory {
    static func make<T>(profile: RuntimeProfile, production: () -> T, testing: () -> T) -> T {
        switch profile {
        case .production: production()
        case .testing: testing()
        }
    }
}
