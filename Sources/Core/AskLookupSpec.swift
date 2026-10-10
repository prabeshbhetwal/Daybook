import Foundation

/// One argument of an Ask lookup, as a model is told about it: its name, what
/// to put there, and whether it may be left out.
struct AskParameter: Equatable {
    let name: String
    let description: String
    let required: Bool
}

/// What a model is told about an Ask lookup: its name, what it returns and the
/// arguments it takes, in the order it lists them. A model sees a lookup only
/// through its spec, so a change here changes what every model is shown.
struct AskLookupSpec: Equatable {
    let name: String
    let description: String
    let parameters: [AskParameter]
}
