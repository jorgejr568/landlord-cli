/// Carries a repository into a child task.
///
/// The repository protocols in `RentivoCore` are `@MainActor`, but their existentials are not
/// `Sendable` — the protocol's isolation says nothing about `any Repository` as a value — so a
/// repository read off `AppDependencies` cannot be handed to an `async let` or to a task group
/// child on its own. Passing it inside this box is safe because nothing is ever *done* with it off
/// the main actor: every member of those protocols is main-actor isolated, so each call hops back
/// before it touches any state. The box only carries the reference as far as that hop.
///
/// It is deliberately the one escape hatch for this, shared by every concurrent load on macOS,
/// rather than a fresh `@unchecked Sendable` wrapper per screen. Nothing but a `@MainActor`
/// repository belongs in it: the safety argument above is the whole of its warrant, and it is not
/// spelled as a generic constraint because the repositories are class-constrained *existentials*,
/// which no `AnyObject` requirement accepts.
struct RepositoryBox<Repository>: @unchecked Sendable {
  let repository: Repository

  init(_ repository: Repository) {
    self.repository = repository
  }
}
