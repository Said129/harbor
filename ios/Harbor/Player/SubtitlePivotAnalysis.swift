import Foundation

@MainActor enum SubtitlePivotAnalysis {
    static func baseLanguage(_ value: String) -> String? {
        guard let code = SubtitleLanguages.normalize(value).split(separator: "-").first,
              code.count == 2 || code.count == 3, code != "und", code != "zxx",
              code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return String(code)
    }

    static func cuesAreHealthy(_ cues: [SubtitlePivotCue], document: SubtitleDocument,
                               language: String, workflow: SubtitlePivotWorkflow) async throws -> Bool {
        let healthy = try await SubtitlePivotEvidence.work {
            guard (8...8_000).contains(cues.count), cues.count == document.cues.count,
                  cues.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start }),
                  cues.filter({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count <= max(1, cues.count / 20) else { return false }
            return !document.text.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0...8, 11, 12, 14...31, 127...159, 0xFFFD: return true
                default: return false
                }
            }
        }
        guard healthy else { return false }
        if language == "ar" { return try await workflow.arabicCueHealth(rawText: document.text, cues: cues) }
        return true
    }

    static func analyze(document: SubtitleDocument, request: SubtitleRequest, source: PlaybackSource, audioID: Int,
                        duration: Double, audioLanguage: String, subtitleLanguage: String, owner: String) async throws -> SubtitleAutoSync.Correction? {
        guard audioLanguage != subtitleLanguage, duration >= 300, (8...8_000).contains(document.cues.count) else { return nil }
        let target = try await SubtitlePivotEvidence.work { try document.structuralCues() }
        let workflow = try await SubtitlePivotEvidence.work { try SubtitlePivotWorkflow() }
        guard try await cuesAreHealthy(target, document: document, language: subtitleLanguage, workflow: workflow) else { return nil }
        let session = UUID()
        defer {
            Task {
                _ = try? await workflow.cancel()
                await SubtitleFileService.shared.cleanup(session)
            }
        }
        let evidence = SubtitlePivotEvidence(source: source, duration: duration, audioID: audioID)
        let input = SubtitlePivotWorkflowInput(audioLanguage: audioLanguage, subtitleLanguage: subtitleLanguage,
            targetCues: target, targetHealthy: true, targetFormatSafe: true, calibrationReady: false, maxCandidates: 3)
        var state = try await workflow.start(input)
        var entries: [String: SubtitlePivotProviderEntry] = [:]
        var prepared: [String: [SubtitlePivotCue]] = [:]
        var consecutiveDrains = 0
        while state.status == "running" {
            try Task.checkCancellation()
            guard owner == (MetadataPreferences.shared.settingsOwner ?? "guest") else { throw CancellationError() }
            guard let operation = state.request else {
                consecutiveDrains += 1
                guard consecutiveDrains <= 16 else { throw HarborError(code: "subtitle-pivot-stalled") }
                await Task.yield()
                state = try await workflow.drain()
                continue
            }
            consecutiveDrains = 0
            do {
                let value: JSONValue
                let candidateID = operation.payload["candidate"]["id"].string ?? ""
                switch operation.operation {
                case "searchPivotCandidates":
                    let results = await SubtitlePivotProviders.search(request: request, source: source, audioLanguage: audioLanguage,
                                                                     owner: owner, workflow: workflow)
                    entries = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    value = try .encoded(results.map(\.candidate))
                case "preparePivotCandidate":
                    guard let entry = entries[candidateID] else { throw HarborError(code: "subtitle-pivot-candidate") }
                    let candidate = try await SubtitlePivotProviders.prepare(entry, language: audioLanguage, request: request, duration: duration, session: session)
                    guard candidate.cues.count * target.count <= 8_000_000 else { throw HarborError(code: "subtitle-pivot-size") }
                    let healthy = try await cuesAreHealthy(candidate.cues, document: candidate.document, language: audioLanguage, workflow: workflow)
                    guard healthy, candidate.formatSafe else { throw HarborError(code: "subtitle-pivot-unsafe") }
                    prepared[candidateID] = candidate.cues
                    value = .object(["cues": try .encoded(candidate.cues), "healthy": .bool(true), "formatSafe": .bool(true)])
                case "validatePivotAgainstAudio":
                    guard let cues = prepared.removeValue(forKey: candidateID) else { throw HarborError(code: "subtitle-pivot-candidate") }
                    value = try await evidence.validatePivot(cues: cues)
                case "validateTargetAgainstAudio":
                    guard let transform = SubtitlePivotTransform(operation.payload["transform"]) else { throw HarborError(code: "subtitle-pivot-transform") }
                    value = try await evidence.validateTarget(cues: target, transform: transform, heldOut: operation.payload["heldOutWindows"].array)
                default: throw HarborError(code: "subtitle-pivot-operation")
                }
                try Task.checkCancellation()
                guard owner == (MetadataPreferences.shared.settingsOwner ?? "guest") else { throw CancellationError() }
                guard try await workflow.complete(requestID: operation.id, result: value) else { throw CancellationError() }
            } catch is CancellationError { throw CancellationError() }
            catch { _ = try await workflow.reject(requestID: operation.id) }
            state = try await workflow.drain()
        }
        guard state.status == "completed", let result = state.result,
              result["decision"]["decision"].string == "offer", let transform = SubtitlePivotTransform(result["transform"]) else { return nil }
        let release = result["candidate"]["releaseScore"].numericValue ?? 0
        let alignment = result["alignment"]["confidence"].numericValue ?? 0
        let audio = result["evidence"]["pivotAudioScore"].numericValue ?? 0
        let confidence = min(0.89, max(0, release * 0.3 + alignment * 0.4 + audio * 0.3))
        let offset = result["transform"]["offsetSec"].numericValue ?? 0
        let ratio = result["transform"]["ratio"].numericValue ?? 1
        return .init(document: document, timing: .init(offset: offset, ratio: ratio, confidence: confidence),
                     origin: .crossLanguage, pivotTransform: transform)
    }
}
