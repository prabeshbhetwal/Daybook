import Foundation

/// How a new AI-made label is drawn (Phase C, ruling C16): from its dominant activity, never from the
/// model. A fixed table, every symbol one the category editor offers and none grey, so the person can
/// change both after keeping it.
enum LabelLook {
    static func look(for purpose: AppPurpose) -> (symbolName: String, hue: WorkTypeHue) {
        switch purpose {
        case .coding: return ("chevron.left.forwardslash.chevron.right", .blue)
        case .writingAI: return ("pencil.and.outline", .purple)
        case .design: return ("paintbrush.pointed.fill", .pink)
        case .communication: return ("bubble.left.and.bubble.right.fill", .teal)
        case .research: return ("magnifyingglass", .green)
        case .media: return ("film.fill", .red)
        case .utility: return ("wrench.and.screwdriver.fill", .brown)
        }
    }
}
