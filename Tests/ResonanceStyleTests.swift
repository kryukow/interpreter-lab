import Foundation

@main struct ResonanceStyleTests {
    static func main() {
        let phases = LabResonancePhase.allCases
        for phase in phases {
            let style = phase.style
            precondition(abs(style.lap) >= 2, "No rapid flashing")
            precondition(style.tail > 0 && style.tail < 1, "One continuous wrapping light")
            precondition(style.halo > 0 && style.halo <= 1)
            precondition(style.light > 0 && style.light <= 1)
            precondition(style.cloud > 0 && style.cloud <= 1)
        }
        precondition(Set(phases.map { $0.style.lap }).count == phases.count)
        precondition(LabResonancePhase.input.style.lap > 0)
        precondition(LabResonancePhase.output.style.lap < 0)
        precondition(LabResonancePhase.processing.style.breath < LabResonancePhase.idle.style.breath)
        print("Graphite orbital phase contracts passed")
    }
}
