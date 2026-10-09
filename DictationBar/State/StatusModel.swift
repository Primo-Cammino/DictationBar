import Observation

@MainActor
@Observable
final class StatusModel {
    private let permissionReader: any PermissionReading
    private let audioAvailabilityService: any AudioAvailabilityProviding

    private(set) var permissions: PermissionSnapshot
    private(set) var recordingAvailability: RecordingAvailability

    init(
        permissionReader: any PermissionReading,
        audioAvailabilityService: any AudioAvailabilityProviding
    ) {
        self.permissionReader = permissionReader
        self.audioAvailabilityService = audioAvailabilityService
        permissions = permissionReader.snapshot()
        recordingAvailability = audioAvailabilityService.availability
    }

    func refresh() {
        permissions = permissionReader.snapshot()
        recordingAvailability = audioAvailabilityService.availability
    }
}
