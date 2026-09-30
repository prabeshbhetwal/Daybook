import Foundation

/// A clock the checks move by hand, so no check depends on the build Mac's time.
final class TestClock {
    var value: Date
    init(_ start: Date) { value = start }
    func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
}

/// Shared assertions for self-test suites. A suite adopts it to call `expect`
/// unqualified; a suite that declares its own `expect` keeps its own.
protocol CheckSuite {}

extension CheckSuite {
    static func expect(_ condition: @autoclosure () -> Bool,
                       _ message: @autoclosure () -> String,
                       _ problems: inout [String]) {
        if !condition() { problems.append(message()) }
    }
}
