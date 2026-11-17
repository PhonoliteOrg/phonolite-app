package com.phonoliteorg.phonolite_app.infrastructure.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory

// Main-thread decoder shared by the session metadata and the notification, so one now-playing
// update decodes its artwork at most once. Bytes are borrowed snapshots that are never mutated.
class ArtworkDecoder {
  companion object {
    private const val MAX_DIMENSION_PX = 512
  }

  private var cachedBytes: ByteArray? = null
  private var cachedBitmap: Bitmap? = null

  fun decode(bytes: ByteArray?): Bitmap? {
    if (bytes == null || bytes.isEmpty()) {
      return null
    }

    // Each channel snapshot carries a fresh array, so identity alone rarely matches; a content
    // comparison is far cheaper than a decode.
    val cached = cachedBytes
    if (cached != null && (cached === bytes || cached.contentEquals(bytes))) {
      cachedBytes = bytes
      return cachedBitmap
    }

    val bitmap = decodeSampled(bytes)
    cachedBytes = bytes
    cachedBitmap = bitmap

    return bitmap
  }

  private fun decodeSampled(bytes: ByteArray): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)

    val largest = maxOf(bounds.outWidth, bounds.outHeight)
    if (largest <= 0) {
      return null
    }

    var sampleSize = 1
    while (largest / sampleSize > MAX_DIMENSION_PX) {
      sampleSize *= 2
    }

    val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }

    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
  }
}
