/// 1st, 2nd, 3rd, 4th, 11th, 22nd: the one place an ordinal is spelt, so the
/// break settings and History's app tile cannot disagree about "12nd".
enum Ordinal {
    static func text(_ number: Int) -> String {
        let suffix: String
        if (11...13).contains(number % 100) {
            suffix = "th"
        } else {
            switch number % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(number)\(suffix)"
    }
}
