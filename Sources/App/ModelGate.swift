import FoundationModels

/// The one question every Apple Intelligence feature asks first: can this Mac
/// use Apple's on-device model right now? Ask and the written notes read it
/// here, so they agree. FoundationModels needs macOS 26, so every use stays
/// behind `#available` and the app still opens on macOS 14.
enum ModelGate {
    /// macOS 26 and a model that is ready, read on every call: it can change
    /// while the app runs (a download finishing, Apple Intelligence switched
    /// on or off in System Settings).
    static var modelAvailable: Bool {
        if #available(macOS 26, *) { return SystemLanguageModel.default.availability == .available }
        return false
    }
}
