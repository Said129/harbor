import Foundation

/// The providers behind Desktop's model ids (`AiProvider` in `src/lib/ai-models.ts`).
enum AISearchProvider: String, CaseIterable, Sendable {
    case openai, anthropic, gemini, meta, mistral, deepseek, xai, qwen, moonshot, nvidia, groq
}

/// Desktop's two AI services (`AiProviderTab`). Each has its own key.
enum AISearchService: String, CaseIterable, Sendable {
    case openrouter, groq
}

struct AISearchModel: Equatable, Sendable {
    let id: String
    let label: String
    let provider: AISearchProvider
    var free = false
    var recommended = false
}

/// Desktop's model catalog and the rules that depend on a model id (`src/lib/ai-models.ts`).
enum AISearchCatalog {
    /// `DEFAULT_AI_MODEL`, used when no model is chosen.
    static let defaultModel = "google/gemma-4-26b-a4b-it:free"

    static let openRouterModels: [AISearchModel] = [
        AISearchModel(id: "google/gemma-4-26b-a4b-it:free", label: "Gemma 4 26B", provider: .gemini, free: true, recommended: true),
        AISearchModel(id: "openai/gpt-oss-20b:free", label: "GPT-OSS 20B", provider: .openai, free: true),
        AISearchModel(id: "nvidia/nemotron-3-super-120b-a12b:free", label: "Nemotron 3 Super 120B", provider: .nvidia, free: true),
        AISearchModel(id: "nvidia/nemotron-3-nano-30b-a3b:free", label: "Nemotron 3 Nano 30B", provider: .nvidia, free: true),
        AISearchModel(id: "google/gemini-3.1-flash-lite", label: "Gemini 3.1 Flash Lite", provider: .gemini, recommended: true),
        AISearchModel(id: "google/gemini-3.5-flash", label: "Gemini 3.5 Flash", provider: .gemini),
        AISearchModel(id: "anthropic/claude-haiku-4.5", label: "Claude Haiku 4.5", provider: .anthropic, recommended: true),
        AISearchModel(id: "anthropic/claude-sonnet-5", label: "Claude Sonnet 5", provider: .anthropic),
        AISearchModel(id: "openai/gpt-4o-mini", label: "GPT-4o mini", provider: .openai),
        AISearchModel(id: "openai/gpt-5.6-sol", label: "GPT-5.6 Sol", provider: .openai),
        AISearchModel(id: "deepseek/deepseek-v4-flash", label: "DeepSeek V4 Flash", provider: .deepseek),
        AISearchModel(id: "qwen/qwen3.6-flash", label: "Qwen 3.6 Flash", provider: .qwen),
        AISearchModel(id: "x-ai/grok-4.5", label: "Grok 4.5", provider: .xai),
        AISearchModel(id: "mistralai/mistral-medium-3-5", label: "Mistral Medium 3.5", provider: .mistral),
        AISearchModel(id: "meta-llama/llama-4-maverick", label: "Llama 4 Maverick", provider: .meta),
        AISearchModel(id: "moonshotai/kimi-k2.5", label: "Kimi K2.5", provider: .moonshot),
    ]

    static let groqModels: [AISearchModel] = [
        AISearchModel(id: "llama-3.3-70b-versatile", label: "Llama 3.3 70B Versatile", provider: .groq, free: true, recommended: true),
        AISearchModel(id: "meta-llama/llama-4-scout-17b-16e-instruct", label: "Llama 4 Scout 17B", provider: .groq, free: true, recommended: true),
        AISearchModel(id: "meta-llama/llama-4-maverick-17b-128e-instruct", label: "Llama 4 Maverick 17B", provider: .groq, free: true),
        AISearchModel(id: "moonshotai/kimi-k2-instruct", label: "Kimi K2 Instruct", provider: .groq, free: true),
        AISearchModel(id: "openai/gpt-oss-120b", label: "GPT-OSS 120B", provider: .groq, free: true, recommended: true),
        AISearchModel(id: "openai/gpt-oss-20b", label: "GPT-OSS 20B", provider: .groq, free: true),
        AISearchModel(id: "qwen/qwen3-32b", label: "Qwen 3 32B", provider: .groq, free: true),
        AISearchModel(id: "llama-3.1-8b-instant", label: "Llama 3.1 8B Instant", provider: .groq, free: true),
    ]

    /// `MODEL_MIGRATIONS`: retired ids that Desktop still finds in saved settings.
    static let migrations: [String: String] = [
        "google/gemini-flash-1.5": "google/gemini-3.1-flash-lite",
        "google/gemini-flash-1.5-8b": "google/gemini-3.1-flash-lite",
        "google/gemini-pro-1.5": "google/gemini-3.5-flash",
        "google/gemini-2.0-flash-001": "google/gemini-3.5-flash",
        "google/gemma-3-27b-it:free": "google/gemma-4-26b-a4b-it:free",
        "deepseek/deepseek-chat-v3-0324:free": "google/gemma-4-26b-a4b-it:free",
        "meta-llama/llama-3.3-70b-instruct:free": "google/gemma-4-26b-a4b-it:free",
        "qwen/qwen-2.5-72b-instruct:free": "google/gemma-4-26b-a4b-it:free",
        "anthropic/claude-3.5-sonnet": "anthropic/claude-sonnet-5",
        "anthropic/claude-3.7-sonnet": "anthropic/claude-sonnet-5",
        "anthropic/claude-3.5-haiku": "anthropic/claude-haiku-4.5",
        "x-ai/grok-2-1212": "x-ai/grok-4.5",
    ]

    /// `JSON_SCHEMA_READY`: model families that accept Desktop's JSON schema.
    static let jsonSchemaPrefixes = ["openai/gpt-4o", "openai/gpt-5", "anthropic/claude-", "google/gemini-3", "google/gemini-2", "deepseek/deepseek-v4"]

    /// `PREFIX_PROVIDER`: the vendor part of an id before the slash.
    static let vendorPrefixes: [String: AISearchProvider] = [
        "openai": .openai,
        "anthropic": .anthropic,
        "google": .gemini,
        "meta-llama": .meta,
        "mistralai": .mistral,
        "deepseek": .deepseek,
        "x-ai": .xai,
        "qwen": .qwen,
        "moonshotai": .moonshot,
        "nvidia": .nvidia,
        "groq": .groq,
    ]

    static let bareGroqPrefixes = ["llama-", "llama3-"]

    static func model(_ id: String) -> AISearchModel? {
        openRouterModels.first { $0.id == id } ?? groqModels.first { $0.id == id }
    }

    /// `providerForModel`: a known catalog entry first, then the id's own prefix, and OpenAI when nothing matches.
    static func provider(for modelID: String) -> AISearchProvider {
        if let known = model(modelID) { return known.provider }
        let lowered = modelID.lowercased()
        if bareGroqPrefixes.contains(where: { lowered.hasPrefix($0) }) { return .groq }
        let vendor = (modelID.components(separatedBy: "/").first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return vendorPrefixes[vendor] ?? .openai
    }

    /// `providerTabFor`: which service a model id belongs to.
    static func service(for modelID: String) -> AISearchService {
        provider(for: modelID) == .groq ? .groq : .openrouter
    }

    /// `migrateModelId`.
    static func migrate(_ id: String) -> String {
        migrations[id] ?? id
    }

    /// The model that a request uses: the migrated id, or the default when nothing is chosen (`migrateModelId(model.trim()) || DEFAULT_AI_MODEL`).
    static func resolvedModel(_ raw: String) -> String {
        let migrated = migrate(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        return migrated.isEmpty ? defaultModel : migrated
    }

    /// `supportsSampling`: Claude Opus and Sonnet 4.6+ and 5 reject a temperature.
    static func supportsSampling(_ id: String) -> Bool {
        id.range(of: #"^anthropic/claude-(?:opus|sonnet)-(?:4[.-][678]|5)"#, options: .regularExpression) == nil
    }

    /// `supportsJsonSchema`: free ":free" variants get prompt-only JSON.
    static func supportsJSONSchema(_ id: String) -> Bool {
        !id.hasSuffix(":free") && jsonSchemaPrefixes.contains { id.hasPrefix($0) }
    }

    /// `modelLabelFor`.
    static func label(for modelID: String) -> String {
        model(modelID)?.label ?? modelID
    }
}
