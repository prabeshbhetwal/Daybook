import SwiftUI

/// What the pointer has picked out, shared by the grid and the rows.
final class HistoryGridLink: ObservableObject {
    @Published var span: DateInterval?   // cells inside stay at full strength
    @Published var day: Date?            // the cell the readout describes

    /// Nothing pointed at, for when the grid or the tree leaves under the pointer.
    func clear() {
        span = nil
        day = nil
    }
}
