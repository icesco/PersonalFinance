import Foundation

enum VoiceRecognitionLocale {
    static func candidates(preferredLanguages: [String], current: Locale, supported: Set<Locale>) -> [Locale] {
        let preferred = preferredLanguages.first.map(Locale.init(identifier:)) ?? current
        guard let language = preferred.language.languageCode else { return [] }
        let matching = supported.filter { $0.language.languageCode == language }
        func key(_ locale: Locale) -> String {
            locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        }
        let preferredKey = key(preferred)
        let currentKey = key(current)
        return matching.sorted {
            func rank(_ locale: Locale) -> Int {
                if key(locale) == preferredKey { return 0 }
                if key(locale) == currentKey { return 1 }
                if locale.region == preferred.region, preferred.region != nil { return 2 }
                return 3
            }
            let left = rank($0), right = rank($1)
            return left == right ? key($0) < key($1) : left < right
        }
    }
}
