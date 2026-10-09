import Foundation

struct BrowserAudioTarget: Equatable, Identifiable {
    let bundleID: String
    let processID: Int32
    let name: String
    var id: String { bundleID + ":" + String(processID) }
}
