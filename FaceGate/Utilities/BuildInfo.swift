import Foundation

enum BuildInfo {
    static let commitHash = "development"
    static let buildDate = "00000000-000000"
    static var identifier: String {
        "\(commitHash)-\(buildDate)"
    }
}
