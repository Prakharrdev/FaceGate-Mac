import Combine
import Foundation
import CoreVideo

/// Manages the face enrollment workflow: capturing multiple reference frames,
/// validating quality, generating embeddings, and storing them encrypted.
final class FaceEnrollmentManager: ObservableObject {
    /// Enrollment progress state.
    @Published var state: EnrollmentState = .idle
    @Published var capturedCount: Int = 0
    @Published var currentQuality: Float = 0
    @Published var statusMessage: String = "Position your face in the frame"

    /// Target number of frames to capture.
    let targetFrameCount = FGConstants.enrollmentFrameCount

    private let cameraManager = CameraManager()
    private let faceDetector = FaceDetector()
    private let faceEmbedder = FaceEmbedder.shared
    private let dataStore = FaceDataStore.shared

    /// Collected embeddings during enrollment.
    private var collectedEmbeddings: [[Float]] = []
    private var totalQuality: Float = 0
    private var framesSinceLastCapture: Int = 0

    /// Minimum frames to skip between captures (gives user time to shift expression).
    private let captureInterval = 15

    /// Camera manager for preview layer binding.
    var camera: CameraManager { cameraManager }

    enum EnrollmentState: Equatable {
        case idle
        case capturing
        case processing
        case success
        case failed(String)
    }

    // MARK: - Enrollment Flow

    /// Start the enrollment process: activate camera and begin capturing face frames.
    func startEnrollment() {
        collectedEmbeddings = []
        totalQuality = 0
        capturedCount = 0
        framesSinceLastCapture = captureInterval  // Allow immediate first capture
        state = .capturing
        statusMessage = "Look at the camera"

        cameraManager.onFrameCaptured = { [weak self] pixelBuffer in
            self?.processEnrollmentFrame(pixelBuffer)
        }

        cameraManager.startCapture()
    }

    /// Cancel the enrollment process and clean up.
    func cancelEnrollment() {
        cameraManager.stopCapture()
        cameraManager.onFrameCaptured = nil
        collectedEmbeddings = []
        state = .idle
        capturedCount = 0
        statusMessage = "Enrollment cancelled"
    }

    /// Re-enroll: delete existing data and start fresh.
    func reEnroll() {
        try? dataStore.delete()
        startEnrollment()
    }

    // MARK: - Frame Processing

    private func processEnrollmentFrame(_ pixelBuffer: CVPixelBuffer) {
        // Skip frames between captures to let user change expression.
        framesSinceLastCapture += 1
        guard framesSinceLastCapture >= captureInterval else { return }
        guard state == .capturing else { return }

        faceDetector.detectFacesWithQuality(in: pixelBuffer) { [weak self] results in
            guard let self = self else { return }

            // Must detect exactly one face.
            guard results.count == 1 else {
                DispatchQueue.main.async {
                    if results.isEmpty {
                        self.statusMessage = "No face detected — look at the camera"
                    } else {
                        self.statusMessage = "Multiple faces detected — only one face allowed"
                    }
                }
                return
            }

            let (face, quality) = results[0]

            DispatchQueue.main.async {
                self.currentQuality = quality
            }

            // Reject low-quality captures.
            guard quality >= FGConstants.minimumCaptureQuality else {
                DispatchQueue.main.async {
                    self.statusMessage = "Poor lighting or angle — adjust position"
                }
                return
            }

            // Crop the face and generate an embedding.
            guard let croppedFace = self.faceDetector.cropFace(from: pixelBuffer, observation: face),
                  let embedding = self.faceEmbedder.generateEmbedding(from: croppedFace) else {
                return
            }

            self.framesSinceLastCapture = 0
            self.collectedEmbeddings.append(embedding)
            self.totalQuality += quality

            DispatchQueue.main.async {
                self.capturedCount = self.collectedEmbeddings.count

                if self.capturedCount >= self.targetFrameCount {
                    self.finishEnrollment()
                } else {
                    let remaining = self.targetFrameCount - self.capturedCount
                    self.statusMessage = "Great! \(remaining) more capture\(remaining == 1 ? "" : "s") needed"
                }
            }
        }
    }

    // MARK: - Finish Enrollment

    private func finishEnrollment() {
        state = .processing
        statusMessage = "Processing face data…"
        cameraManager.stopCapture()
        cameraManager.onFrameCaptured = nil

        let enrollment = FaceEnrollment(
            embeddings: collectedEmbeddings,
            enrolledDate: Date(),
            averageQuality: totalQuality / Float(collectedEmbeddings.count)
        )

        do {
            try dataStore.save(enrollment)

            // Enable face unlock by default after successful enrollment.
            UserDefaults.standard.set(true, forKey: FGConstants.faceUnlockEnabledKey)

            state = .success
            statusMessage = "Face enrolled successfully!"
        } catch {
            state = .failed("Failed to save: \(error.localizedDescription)")
            statusMessage = "Enrollment failed"
        }
    }
}
