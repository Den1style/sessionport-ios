import SwiftUI

// MARK: - Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ru
    var id: String { rawValue }

    /// Resolved two-letter code actually used for strings/prompts.
    var code: String {
        switch self {
        case .system:
            let pref = Locale.preferredLanguages.first ?? "en"
            return pref.hasPrefix("ru") ? "ru" : "en"
        case .en: return "en"
        case .ru: return "ru"
        }
    }
}

// MARK: - Settings store (shared via App Group)

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private let kTheme    = "sp_theme"
    private let kLanguage = "sp_language"

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: kTheme) }
    }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: kLanguage) }
    }

    /// Convenience: resolved code for the currently selected language.
    var langCode: String { language.code }

    private init() {
        defaults = UserDefaults(suiteName: "group.com.lusine.sessionport") ?? .standard
        theme    = AppTheme(rawValue: defaults.string(forKey: kTheme) ?? "") ?? .system
        language = AppLanguage(rawValue: defaults.string(forKey: kLanguage) ?? "") ?? .system
    }
}
