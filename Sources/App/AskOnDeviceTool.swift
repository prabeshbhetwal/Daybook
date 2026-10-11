import Foundation
import FoundationModels

/// The one tool shape the on-device model is handed, built from a catalogue
/// entry: one string argument for each parameter, the entry's name and
/// description. The schema is the one `@Generable` arguments gave each of
/// version one's tools (checked byte for byte), so the model is offered
/// exactly what it was before the lookups were defined once.
@available(macOS 26, *)
struct AskOnDeviceTool: Tool {
    typealias Arguments = GeneratedContent

    let name: String
    let description: String
    let parameters: GenerationSchema
    private let argumentNames: [String]
    private let model: AskModel
    /// The session this tool was built for; see `AskModel.generation`.
    private let generation: Int

    /// Throws only if the entry names a parameter twice.
    init(_ lookup: AskLookup, model: AskModel, generation: Int) throws {
        name = lookup.spec.name
        description = lookup.spec.description
        parameters = try Self.schema(for: lookup.spec)
        argumentNames = lookup.spec.parameters.map(\.name)
        self.model = model
        self.generation = generation
    }

    /// An object named `Arguments`, as `@Generable` named version one's, with
    /// a string for each parameter, optional unless the entry requires it.
    static func schema(for spec: AskLookupSpec) throws -> GenerationSchema {
        let properties = spec.parameters.map {
            DynamicGenerationSchema.Property(name: $0.name, description: $0.description,
                                             schema: DynamicGenerationSchema(type: String.self),
                                             isOptional: !$0.required)
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Arguments", properties: properties),
                                    dependencies: [])
    }

    /// An argument the model left out, or sent as something other than text,
    /// is absent; the catalogue says what that means for each lookup.
    func call(arguments: GeneratedContent) async -> String {
        var sent: [String: String] = [:]
        for argument in argumentNames {
            if let value = try? arguments.value(String.self, forProperty: argument) { sent[argument] = value }
        }
        return await model.lookup(name: name, arguments: sent, generation: generation)
    }
}
