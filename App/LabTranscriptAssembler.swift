import Foundation

/// Apple Speech reports *hypotheses*, not cumulative transcript chunks.
/// A hypothesis can be rewritten or restart at a shorter phrase. Keep already
/// spoken segments independently so they never disappear from the UI.
struct LabTranscriptAssembler {
    private(set) var committed: [String] = []
    private(set) var active = ""

    var text: String {
        let parts = committed + (active.isEmpty ? [] : [active])
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    mutating func accept(_ hypothesis: String) -> String {
        let incoming = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return text }
        if active.isEmpty {
            active = removingOverlap(incoming)
            return text
        }

        // A normal partial correction is allowed to replace ONLY the active
        // segment. A reset to new words must not wipe out previous speech.
        if looksLikeNewSegment(previous: active, incoming: incoming) {
            commitActive()
            active = removingOverlap(incoming)
        } else if resemblesRollback(previous: active, incoming: incoming) {
            // Apple's intermediate hypothesis temporarily regressed: keep
            // the longer candidate on screen until a stable correction arrives.
        } else {
            active = incoming
        }
        return text
    }

    mutating func commitActive() {
        let item = active.trimmingCharacters(in: .whitespacesAndNewlines)
        if !item.isEmpty { committed.append(item) }
        active = ""
    }

    mutating func reset() {
        committed = []
        active = ""
    }

    private func resemblesRollback(previous: String, incoming: String) -> Bool {
        let old = normalized(previous)
        let next = normalized(incoming)
        // Apple can revise the middle of a previously long utterance while
        // rebuilding a fresh short hypothesis. Preserve its longer version
        // until the revised one is substantial again.
        let beginsSimilarly = words(old).prefix(3) == words(next).prefix(3)
        return old.count > next.count + 15 && next.count >= 6
            && (old.hasPrefix(next) || (beginsSimilarly && Double(next.count) * 1.4 < Double(old.count)))
    }

    private func looksLikeNewSegment(previous: String, incoming: String) -> Bool {
        let prior = normalized(previous)
        let next = normalized(incoming)
        guard previous.count >= 40, !next.isEmpty else { return false }
        let priorWords = words(prior)
        let nextWords = words(next)
        guard priorWords.count >= 7 else { return false }
        // A major shortening with a different opening is evidence of a fresh
        // partial chunk. Not merely punctuation or a couple corrected words.
        let strongShrink = Double(next.count) * 1.55 + 14 < Double(prior.count)
        let oldOpening = priorWords.prefix(3).joined(separator: " ")
        let newOpening = nextWords.prefix(3).joined(separator: " ")
        let sameBeginning = oldOpening == newOpening || prior.hasPrefix(next)
        let entireNewTextAlreadyInOld = prior.contains(next) && next.count >= 15
        return strongShrink && !sameBeginning && !entireNewTextAlreadyInOld
    }

    private func removingOverlap(_ candidate: String) -> String {
        guard let previous = committed.last else { return candidate }
        let oldWords = words(normalized(previous))
        let newWords = words(normalized(candidate))
        let count = min(oldWords.count, newWords.count, 12)
        guard count >= 2 else { return candidate }
        for overlap in stride(from: count, through: 2, by: -1) {
            if Array(oldWords.suffix(overlap)) == Array(newWords.prefix(overlap)) {
                // Preserve original capitalization/punctuation of incoming
                // after dropping repeated *whole* words.
                let originalWords = candidate.split(whereSeparator: { $0.isWhitespace })
                if overlap < originalWords.count {
                    return originalWords.dropFirst(overlap).joined(separator: " ")
                }
                return ""
            }
        }
        return candidate
    }

    private func words(_ value: String) -> [String] {
        value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private func normalized(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
