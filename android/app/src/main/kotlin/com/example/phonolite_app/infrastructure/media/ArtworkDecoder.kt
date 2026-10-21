package com.example.phonolite_app.infrastructure.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory

class ArtworkDecoder {
  fun decode(bytes: ByteArray?): Bitmap? {
    if (bytes == null || bytes.isEmpty()) {
      return null
    }

    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
  }
}
