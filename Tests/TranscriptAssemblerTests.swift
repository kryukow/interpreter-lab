import Foundation

@main
struct TranscriptAssemblerTests {
    static func main() {
        var text = LabTranscriptAssembler()
        let opening = "Сегодня мы поехали на объект чтобы закончить монтаж отопления и провести проверку всех соединений"
        assert(text.accept("Сегодня мы поехали на объект") == "Сегодня мы поехали на объект")
        assert(text.accept(opening) == opening)
        let continuation = "После этого я проверил насос и обнаружил что давление начало постепенно падать"
        let combined = text.accept("После этого я проверил насос")
        assert(combined.contains(opening), "A new short hypothesis must never erase earlier speech")
        assert(combined.contains("После этого я проверил насос"))
        let finished = text.accept(continuation)
        assert(finished.contains(opening), "First segment must survive correction of the second")
        assert(finished.contains(continuation))

        // Revisions of the same unfinished phrase replace only that hypothesis.
        var corrected = LabTranscriptAssembler()
        corrected.accept("Я поменял правый датчик давления и установил старую прокладку")
        corrected.accept("Я поменял левый датчик давления и установил новую прокладку")
        assert(!corrected.text.contains("правый"))
        assert(corrected.text.contains("левый"))

        // A rollback to a short prefix must not make the whole UI disappear.
        var rollback = LabTranscriptAssembler()
        rollback.accept(opening)
        assert(rollback.accept("Сегодня мы поехали") == opening)

        // Finalizing a recognition task stores completed speech without starting
        // a duplicate new paragraph in the following task.
        var rotated = LabTranscriptAssembler()
        rotated.accept("Я поменял фильтр и проверил давление топлива")
        rotated.commitActive()
        let after = rotated.accept("проверил давление топлива снова")
        assert(after == "Я поменял фильтр и проверил давление топлива снова",
               "Repeated words at segment boundaries must be removed")

        rotated.reset()
        assert(rotated.text.isEmpty)
        print("Transcript assembler: accumulation, corrections, rollback, overlap, reset passed")
    }
}
