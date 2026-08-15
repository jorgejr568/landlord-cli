import Testing

#if !canImport(RentivoCore)
  @testable import Rentivo

  private enum Probe: Hashable {
    case first
    case second
    case review
  }

  @Test func wizardFlowAdvancesRetreatsAndClampsAtItsBounds() {
    var flow = RentivoWizardFlow(steps: [Probe.first, .second, .review])
    #expect(flow.progressLabel == "Etapa 1 de 3")
    #expect(flow.retreat() == false)
    #expect(flow.advance() == true)
    #expect(flow.current == .second)
    #expect(flow.advance() == true)
    #expect(flow.isLast)
    #expect(flow.advance() == false)
  }
#endif
