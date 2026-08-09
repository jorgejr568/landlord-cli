package app.rentivo.features.bills

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import app.rentivo.data.DownloadedFileStore
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.domain.DownloadedFile

/**
 * Presents [DownloadShareView] for [file] and removes the downloaded file from the cache once that
 * sheet is gone. Port of `ios/Rentivo/Features/Bills/DownloadedFileSheet.swift`.
 *
 * The removal is driven by the parameter losing its value, never from inside [DownloadShareView]:
 * while that sheet is on screen the share intent still needs the file on disk. Tracking the
 * *previous* value is what identifies the file to remove — the current one is already gone by then
 * — and it also covers one download replacing another without an intervening dismissal.
 *
 * Leaving the screen is the case that transition can never see: the composable goes away without
 * [file] ever going null, so the disposal below is what stops an invoice or receipt PDF from
 * sitting in the cache until sign-out.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadedFileSheet(file: DownloadedFile?, onDismiss: () -> Unit) {
  var previous by remember { mutableStateOf<DownloadedFile?>(null) }
  LaunchedEffect(file) {
    val stale = previous
    previous = file
    if (stale != null) DownloadedFileStore.remove(stale)
  }

  // Both are cleaned up: `previous` may still hold a file the effect above has not yet retired
  // (the sheet can be torn down in the same frame the parameter changes), and `current` is the one
  // on screen. `remove` is best-effort, so removing the same file twice is harmless. `current` is
  // read through `rememberUpdatedState` because a keyless `DisposableEffect` would otherwise
  // dispose with the parameter value from the composition that installed it.
  val current by rememberUpdatedState(file)
  DisposableEffect(Unit) {
    onDispose {
      previous?.let(DownloadedFileStore::remove)
      current?.let(DownloadedFileStore::remove)
    }
  }

  if (file == null) return
  ModalBottomSheet(
    onDismissRequest = onDismiss,
    sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    containerColor = RentivoColors.paper,
  ) {
    DownloadShareView(file = file, onDismiss = onDismiss)
  }
}

/** The share/save surface for one downloaded document. */
@Composable
fun DownloadShareView(file: DownloadedFile, onDismiss: () -> Unit) {
  val context = LocalContext.current

  Column(
    modifier = Modifier
      .fillMaxWidth()
      .padding(RentivoSpacing.page),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
      Text(
        text = "Prévia",
        style = RentivoTypography.cardTitle,
        color = RentivoColors.ink,
        modifier = Modifier.weight(1f),
      )
      TextButton(onClick = onDismiss) { Text(text = "Concluir") }
    }
    Icon(
      imageVector = Icons.Filled.Description,
      contentDescription = null,
      tint = RentivoColors.blue,
      modifier = Modifier.size(64.dp),
    )
    Text(text = file.filename, style = RentivoTypography.title, color = RentivoColors.ink)
    Text(
      text = "Arquivo baixado do Rentivo.",
      style = RentivoTypography.subheadline,
      color = RentivoColors.secondaryInk,
    )
    RentivoButton(onClick = { context.startActivity(shareChooser(context, file)) }) {
      Icon(imageVector = Icons.Filled.Share, contentDescription = null, tint = Color.White)
      Text(
        text = "Compartilhar ou salvar arquivo",
        style = RentivoTypography.caption,
        color = Color.White,
        modifier = Modifier.padding(start = RentivoSpacing.small),
      )
    }
  }
}

/**
 * Builds the system share chooser for [file]. The document lives in the app's private cache, so it
 * is handed over as a `content://` URI minted by the manifest-declared [FileProvider] together with
 * a one-shot read grant — the only way another app can open it.
 */
private fun shareChooser(context: Context, file: DownloadedFile): Intent {
  val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file.file)
  val send = Intent(Intent.ACTION_SEND).apply {
    type = file.mediaType
    putExtra(Intent.EXTRA_STREAM, uri)
    putExtra(Intent.EXTRA_TITLE, file.filename)
    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
  }
  return Intent.createChooser(send, "Compartilhar ou salvar arquivo")
}
