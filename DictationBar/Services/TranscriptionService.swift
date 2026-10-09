import Foundation

enum TranscriptionFailure: LocalizedError, Equatable {
    case tooLarge, invalidKey, rateLimited, server, network, invalidResponse, cancelled

    var errorDescription: String? {
        switch self {
        case .tooLarge: "Die WAV überschreitet das Limit von 60 Minuten oder 500 MB. Die Datei bleibt erhalten."
        case .invalidKey: "Mistral hat den API-Key abgelehnt. Bitte den Key in den Einstellungen korrigieren."
        case .rateLimited: "Mistrals Anfragelimit ist erreicht. Du kannst später bewusst erneut transkribieren."
        case .server: "Mistral konnte den Auftrag nicht abschließen. Die Aufnahme bleibt zum erneuten Versuch erhalten."
        case .network: "Die Verbindung zu Mistral ist fehlgeschlagen oder abgelaufen. Die WAV bleibt erhalten."
        case .invalidResponse: "Mistral hat keinen gültigen Text geliefert. Die Aufnahme bleibt erhalten."
        case .cancelled: "Transkription abgebrochen. Die Aufnahme bleibt zum erneuten Versuch erhalten."
        }
    }
}

protocol TranscriptionProviding {
    func transcribe(file: URL) async throws -> String
    /// Returns the HTTP status of an authenticated, audio-free request.
    func verifyKey() async throws -> Int
    func cancel() async
}

struct HTTPUploadResponse {
    let status: Int
    let body: Data
}

protocol HTTPUploading {
    func upload(request: URLRequest, bodyFile: URL) async throws -> HTTPUploadResponse
    func cancel() async
}
