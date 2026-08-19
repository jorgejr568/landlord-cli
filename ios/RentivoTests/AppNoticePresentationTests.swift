import Foundation
import Testing

@testable import Rentivo

@MainActor
@Suite(.serialized)
struct AppNoticePresentationTests {
  @Test func standardAndVoiceOverLifetimesAreScheduledFromMount() async throws {
    let clock = ControllableNoticeClock()
    let app = makeApp(clock: clock)

    app.showNotice("Primeiro aviso.", owner: .home)
    let standardID = try #require(app.notice?.id)
    app.noticeDidMount(id: standardID, voiceOverEnabled: false)
    await clock.waitForSleepCount(1)
    #expect(clock.requestedDurations == [4])

    app.showNotice("Aviso acessível.", owner: .home)
    let accessibleID = try #require(app.notice?.id)
    app.noticeDidMount(id: accessibleID, voiceOverEnabled: true)
    await clock.waitForSleepCount(2)
    #expect(clock.requestedDurations == [4, 8])

    clock.advance(by: 8)
    await settle()
  }

  @Test func noticeRemainsUntilItsDeadlineThenDismisses() async throws {
    let clock = ControllableNoticeClock()
    let app = makeApp(clock: clock)

    app.showNotice("Cobrança salva.", owner: .billings)
    let id = try #require(app.notice?.id)
    app.noticeDidMount(id: id, voiceOverEnabled: false)
    await clock.waitForSleepCount(1)

    clock.advance(by: 3.99)
    #expect(app.notice?.id == id)
    clock.advance(by: 0.01)
    await settle()
    #expect(app.notice == nil)
  }

  @Test func replacementGetsANewIdentityAndStaleDeadlineCannotDismissIt() async throws {
    let clock = ControllableNoticeClock()
    let app = makeApp(clock: clock)

    app.showNotice("Mesmo texto.", owner: .home)
    let firstID = try #require(app.notice?.id)
    app.noticeDidMount(id: firstID, voiceOverEnabled: false)
    await clock.waitForSleepCount(1)
    clock.advance(by: 2)

    app.showNotice("Mesmo texto.", owner: .home)
    let replacementID = try #require(app.notice?.id)
    #expect(replacementID != firstID)
    app.noticeDidMount(id: replacementID, voiceOverEnabled: false)
    await clock.waitForSleepCount(2)

    clock.advance(by: 2)
    await settle()
    #expect(app.notice?.id == replacementID)

    clock.advance(by: 2)
    await settle()
    #expect(app.notice == nil)
  }

  @Test func closeAndCommittedSwipeUseImmediateDismissal() throws {
    let app = makeApp()

    app.showNotice("Fechar.", owner: .account)
    let closeID = try #require(app.notice?.id)
    app.dismissNotice(id: closeID)
    #expect(app.notice == nil)

    app.showNotice("Arrastar.", owner: .account)
    let swipeID = try #require(app.notice?.id)
    app.noticeInteractionEnded(id: swipeID, committed: true)
    #expect(app.notice == nil)
  }

  @Test func cancelledSwipeResumesRemainingLifetimeWithOneSecondMinimum() async throws {
    let clock = ControllableNoticeClock()
    let app = makeApp(clock: clock)

    app.showNotice("Arrastar.", owner: .security)
    let id = try #require(app.notice?.id)
    app.noticeDidMount(id: id, voiceOverEnabled: false)
    await clock.waitForSleepCount(1)

    clock.advance(by: 3.75)
    app.noticeInteractionBegan(id: id)
    app.noticeInteractionEnded(id: id, committed: false)
    await clock.waitForSleepCount(2)

    #expect(clock.requestedDurations == [4, 1])
    #expect(app.notice?.id == id)

    clock.advance(by: 0.25)
    await settle()
    #expect(app.notice?.id == id)
    clock.advance(by: 0.75)
    await settle()
    #expect(app.notice == nil)
  }

  @Test func areaChangesDismissOnlyNoticesOwnedByAnotherArea() {
    let app = makeApp()
    app.activateNoticeArea(.security)
    app.showNotice("Senha alterada com sucesso.")

    app.activateNoticeArea(.security)
    #expect(app.notice?.owner == .security)

    app.activateNoticeArea(.apiKeys)
    #expect(app.notice == nil)
  }

  @Test func sceneDeactivationAndSessionCleanupDismissImmediately() async {
    let app = makeApp()
    app.showNotice("Aviso temporário.", owner: .home)
    app.sceneDidBecomeInactive()
    #expect(app.notice == nil)

    app.signIn()
    #expect(app.notice?.owner == .home)
    await app.signOut()
    #expect(app.notice == nil)
  }

  private func makeApp(clock: ControllableNoticeClock? = nil) -> AppModel {
    AppModel(
      store: MockRentivoStore(fixtures: .canonical),
      noticeClock: clock?.clock ?? .continuous
    )
  }

  private func settle() async {
    for _ in 0..<4 { await Task.yield() }
  }
}

@MainActor
private final class ControllableNoticeClock {
  var now: TimeInterval = 0
  private(set) var requestedDurations: [TimeInterval] = []
  private struct Sleep {
    let deadline: TimeInterval
    let continuation: CheckedContinuation<Void, any Error>
  }
  private var sleeps: [Sleep] = []

  lazy var clock = AppNoticeClock(
    now: { [unowned self] in now },
    sleep: { [unowned self] duration in
      requestedDurations.append(duration)
      try await withCheckedThrowingContinuation { continuation in
        sleeps.append(Sleep(deadline: now + duration, continuation: continuation))
      }
    }
  )

  func waitForSleepCount(_ count: Int) async {
    while requestedDurations.count < count { await Task.yield() }
  }

  func advance(by duration: TimeInterval) {
    now += duration
    let ready = sleeps.filter { $0.deadline <= now }
    sleeps.removeAll { $0.deadline <= now }
    ready.forEach { $0.continuation.resume() }
  }
}
