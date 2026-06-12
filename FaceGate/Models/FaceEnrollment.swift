import Foundation

/// Model representing a user's face enrollment data.
/// Contains the reference embeddings captured during enrollment,
/// along with metadata about when and how the enrollment was created.
struct FaceEnrollment: Codable {
    /// The face embedding vectors captured during enrollment.
    /// Each vector is a 512-dimensional Float array from MobileFaceNet (InsightFace w600k).
    let embeddings: [[Float]]

    /// Timestamp of when the enrollment was created.
    let enrolledDate: Date

    /// Average capture quality score across all enrollment frames (0.0–1.0).
    let averageQuality: Float

    /// Number of valid frames captured during enrollment.
    var frameCount: Int {
        embeddings.count
    }

    /// Whether the enrollment has enough embeddings to be considered valid.
    var isValid: Bool {
        embeddings.count >= 3
    }
}
