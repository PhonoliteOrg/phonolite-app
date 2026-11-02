package com.phonoliteorg.phonolite_app.infrastructure.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper

/** Subscriber-owned default-route observation; all state is confined to the main thread. */
class NetworkRouteMonitor(context: Context) {
  private val manager = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
  private val mainHandler = Handler(Looper.getMainLooper())
  private var callback: ConnectivityManager.NetworkCallback? = null
  private var publish: ((Long) -> Unit)? = null
  private var signature: String? = null
  private var generation = 0L
  private var revision = 0L

  fun start(onRevision: (Long) -> Unit) {
    stop()

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
      throw UnsupportedOperationException("Default-network callbacks require Android 7")
    }

    val observation = generation
    val callback = object : ConnectivityManager.NetworkCallback() {
      override fun onAvailable(network: Network) = scheduleRefresh(observation)
      override fun onLost(network: Network) = scheduleRefresh(observation)
      override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) = scheduleRefresh(observation)
      override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = scheduleRefresh(observation)
    }

    manager.registerDefaultNetworkCallback(callback)
    this.callback = callback
    publish = onRevision
    scheduleRefresh(observation)
  }

  fun stop() {
    generation++
    val previous = callback
    callback = null
    publish = null
    signature = null

    if (previous != null) {
      try {
        manager.unregisterNetworkCallback(previous)
      } catch (_: IllegalArgumentException) {
        // Already unregistered during engine/channel teardown.
      }
    }
  }

  private fun scheduleRefresh(observation: Long) {
    mainHandler.post {
      if (observation != generation || callback == null) {
        return@post
      }

      val current = currentSignature()

      if (signature != current) {
        signature = current
        revision++
        publish?.invoke(revision)
      }
    }
  }

  private fun currentSignature(): String {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      return "unsupported"
    }

    val network = manager.activeNetwork ?: return "offline"
    val properties = manager.getLinkProperties(network)
    val capabilities = manager.getNetworkCapabilities(network)
    val transports = listOf(
      NetworkCapabilities.TRANSPORT_WIFI,
      NetworkCapabilities.TRANSPORT_CELLULAR,
      NetworkCapabilities.TRANSPORT_ETHERNET,
      NetworkCapabilities.TRANSPORT_VPN,
      NetworkCapabilities.TRANSPORT_BLUETOOTH
    ).filter { capabilities?.hasTransport(it) == true }

    return listOf(
      network.toString(),
      properties?.interfaceName.orEmpty(),
      properties?.linkAddresses?.map { it.toString() }?.sorted().toString(),
      properties?.routes?.map { it.toString() }?.sorted().toString(),
      properties?.dnsServers?.mapNotNull { it.hostAddress }?.sorted().toString(),
      transports.toString(),
      capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED).toString()
    ).joinToString("|")
  }
}
