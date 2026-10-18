import Foundation

/// Looks up a string from Localizable.strings at runtime, for keys that are not literals
/// (literals in SwiftUI's Text, Button and Alert are localized automatically).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Localized format string, e.g. L("Page %ld", 2).
func L(_ key: String, _ args: CVarArg...) -> String { String(format: L(key), arguments: args) }
