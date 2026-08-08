package app.rentivo.data

/**
 * The live app has no demo switches to flip, so this satisfies [DemoRepository] for the live
 * dependency graph while every demo setting stays at its inert default.
 */
class LiveDemoRepository : DemoRepository {

  override var demoSettings: DemoSettings = DemoSettings.standard
    private set

  override fun failNextOperation() = Unit

  override fun setEmptyMode(enabled: Boolean) {
    demoSettings = demoSettings.copy(emptyMode = enabled)
  }

  override fun setViewerMode(enabled: Boolean) {
    demoSettings = demoSettings.copy(viewerMode = enabled)
  }

  override fun setDelayEnabled(enabled: Boolean) {
    demoSettings = demoSettings.copy(delayEnabled = enabled)
  }

  override fun reset() {
    demoSettings = DemoSettings.standard
  }
}
