import AVFoundation
import CoreAudio
import Foundation

struct Microphone: Identifiable, Equatable {
    let id: String
    let name: String
    var isBluetooth = false
    var isSystemDefault = false
}

enum MicrophoneRouting {
    static func preferred(_ devices: [Microphone], configuredID: String?, automaticBluetooth: Bool) -> Microphone? {
        if automaticBluetooth {
            let bluetooth = devices.filter(\.isBluetooth)
            if let selected = bluetooth.first(where: { $0.id == configuredID }) { return selected }
            if let preferred = bluetooth.first(where: \.isSystemDefault) { return preferred }
            if let first = bluetooth.min(by: { $0.id < $1.id }) { return first }
        }
        return devices.first { $0.id == configuredID }
    }
}

@MainActor
protocol MicrophoneProviding: AnyObject {
    var onDevicesChanged: (() -> Void)? { get set }
    func startMonitoring()
    func stopMonitoring()
    func microphones() -> [Microphone]
    func requestAccess() async -> Bool
}

extension MicrophoneProviding {
    var onDevicesChanged: (() -> Void)? { get { nil } set { } }
    func startMonitoring() { }
    func stopMonitoring() { }
}

@MainActor
final class MicrophoneService: MicrophoneProviding {
    var onDevicesChanged: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    func microphones() -> [Microphone] {
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
            .filter { $0.isConnected && $0.hasMediaType(.audio) }
            .map {
                Microphone(id: $0.uniqueID, name: $0.localizedName,
                    isBluetooth: UInt32(bitPattern: $0.transportType) == kAudioDeviceTransportTypeBluetooth || UInt32(bitPattern: $0.transportType) == kAudioDeviceTransportTypeBluetoothLE,
                    isSystemDefault: $0.uniqueID == defaultID)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func startMonitoring() {
        guard observers.isEmpty else { return }
        for name in [Notification.Name.AVCaptureDeviceWasConnected, .AVCaptureDeviceWasDisconnected] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onDevicesChanged?() }
            })
        }
    }

    func stopMonitoring() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
