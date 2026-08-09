package app.rentivo.app

/** The four root tabs of the app shell, mirroring the iOS `AppTab` enum. */
enum class AppTab {
  HOME,
  BILLINGS,
  ORGANIZATIONS,
  ACCOUNT,
}

/**
 * A transient, app-level message rendered by `NoticeBanner`.
 *
 * The iOS type carries a `UUID` id purely so SwiftUI can re-trigger its transition when one notice
 * replaces another. Compose keys on the state object itself, so no id is needed here: two notices
 * with the same kind and message are interchangeable, which is exactly the desired behavior.
 */
data class AppNotice(val kind: Kind, val message: String) {
  enum class Kind {
    SUCCESS,
    INFORMATION,
    WARNING,
  }
}
