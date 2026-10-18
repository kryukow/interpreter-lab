import Foundation

@main
struct StreamTests {
    static func main() throws {
        var good = LabResponseStream()
        try good.ingest(["type": "response.created"])
        try good.ingest(["type": "response.output_text.delta", "delta": "Guten "])
        try good.ingest(["type": "response.output_text.delta", "delta": "Tag."])
        try good.ingest(["type": "response.output_text.done", "text": "Guten Tag."])
        try good.ingest(["type": "response.completed"])
        assert(try good.finish() == "Guten Tag.")

        var completedOnly = LabResponseStream()
        try completedOnly.ingest([
            "type": "response.completed",
            "response": [
                "output": [[
                    "type": "message",
                    "content": [["type": "output_text", "text": "Hallo!"]]
                ]]
            ]
        ])
        assert(try completedOnly.finish() == "Hallo!")

        var incomplete = LabResponseStream()
        try incomplete.ingest(["type": "response.output_text.delta", "delta": "Half"])
        do { _ = try incomplete.finish(); assertionFailure("Must reject missing completion") }
        catch LabResponseStream.StreamError.interrupted {}

        var failed = LabResponseStream()
        do {
            try failed.ingest([
                "type": "response.failed",
                "response": ["error": [
                    "code": "subscription_sharing_usage_limit_exceeded",
                    "message": "Rate limit reached.",
                    "param": "model"
                ]]
            ])
            assertionFailure("Must reject response.failed")
        } catch {
            let text = error.localizedDescription
            assert(text.contains("subscription_sharing_usage_limit_exceeded"))
            assert(text.contains("model"))
        }

        let admission = LabResponseStream.errorText(
            ["detail": "direct admission rejected"],
            fallback: "unknown"
        )
        assert(admission == "direct admission rejected")
        print("LabResponseStream: 5 independent checks passed")
    }
}
