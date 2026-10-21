package com.example.phonolite_app.bootstrap

import android.app.Application

class PhonoliteApplication : Application() {
  val nativeHost: NativeHost by lazy { NativeHost(this) }

  override fun onCreate() {
    super.onCreate()
    nativeHost.startInitialization()
  }
}
