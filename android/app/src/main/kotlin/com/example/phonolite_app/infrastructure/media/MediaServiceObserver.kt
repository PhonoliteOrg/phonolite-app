package com.example.phonolite_app.infrastructure.media

interface MediaServiceObserver {
  fun applyState()
  fun clearState()
  fun onSourcesChanged()
}
