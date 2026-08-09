package app.rentivo.data

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * Pins the two halves of the FileProvider coupling together.
 *
 * `res/xml/file_paths.xml` is what the provider reads at runtime, and a directory missing from it
 * fails only on a real device: the share sheet cannot read a download, and the camera app cannot
 * write a capture. Renaming a store's directory constant without touching the resource is the
 * plausible drift, so the resource is parsed here as a plain file — the unit-test JVM has no
 * resource table — and compared against the constant.
 */
class FileProviderPathsTest {

  @Test
  fun `the captures directory is exposed to the FileProvider`() {
    val paths = cachePaths()

    assertTrue(
      "file_paths.xml exposes $paths, which does not cover ${ReceiptCaptureStore.DIRECTORY_NAME}",
      ReceiptCaptureStore.DIRECTORY_NAME in paths.values,
    )
    assertEquals(ReceiptCaptureStore.DIRECTORY_NAME, paths["captures"])
  }

  @Test
  fun `nothing beyond the two owned cache subdirectories is shared`() {
    // The cache root or an empty path would expose every scratch file the app writes.
    val paths = cachePaths()

    assertEquals(setOf("captures", "downloads"), paths.keys)
    assertTrue(paths.values.none { it.isEmpty() || it == "." })
  }

  /** The `cache-path` entries as name to directory, with the resource's trailing slash removed. */
  private fun cachePaths(): Map<String, String> {
    val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(filePathsXml())
    val entries = document.getElementsByTagName("cache-path")
    return (0 until entries.length)
      .map { entries.item(it) as Element }
      .associate { it.getAttribute("name") to it.getAttribute("path").trimEnd('/') }
  }

  /**
   * Gradle runs unit tests from the module directory, but the file is looked up from a couple of
   * plausible roots so the test does not depend on which one a given runner picks.
   */
  private fun filePathsXml(): File {
    val relative = "src/main/res/xml/file_paths.xml"
    val roots = listOf(File("."), File("app"), File("android/app"))
    return roots.map { File(it, relative) }.firstOrNull { it.isFile }
      ?: error("Could not find $relative from ${File(".").absolutePath}")
  }
}
