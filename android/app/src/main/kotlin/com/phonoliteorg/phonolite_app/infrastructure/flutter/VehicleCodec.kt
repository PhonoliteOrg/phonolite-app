package com.phonoliteorg.phonolite_app.infrastructure.flutter

import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleBrowseResult
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleEntry
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleLibraryStatus
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleScope

class VehicleCodec {
  fun decodeLibraryStatus(value: Any?): VehicleLibraryStatus {
    val values = value as? Map<*, *>

    return VehicleLibraryStatus(likedAvailable = values?.get("likedAvailable") as? Boolean ?: false)
  }

  fun decodeEntries(value: Any?): VehicleBrowseResult {
    val values = value as? Map<*, *> ?: return VehicleBrowseResult(error = "Unavailable")
    val error = values["error"]?.toString()

    if (!error.isNullOrBlank()) {
      return VehicleBrowseResult(error = error)
    }

    val rawItems = values["items"] as? List<*> ?: emptyList<Any?>()
    val items = rawItems.mapNotNull { raw ->
      val item = raw as? Map<*, *> ?: return@mapNotNull null
      val id = item["id"]?.toString().orEmpty()
      val title = item["title"]?.toString().orEmpty()

      if (id.isEmpty() || title.isEmpty()) {
        return@mapNotNull null
      }

      VehicleEntry(id, title, item["subtitle"]?.toString(), item["enabled"] as? Boolean ?: true)
    }

    return VehicleBrowseResult(items = items)
  }

  fun failure(error: String?, notImplemented: Boolean): VehicleBrowseResult =
    VehicleBrowseResult(error = if (notImplemented) "Phonolite is still loading" else error)

  fun arguments(scope: VehicleScope, name: String? = null, value: String? = null): Map<String, Any?>? {
    val values = mutableMapOf<String, Any?>()

    if (scope == VehicleScope.LOCAL) {
      values["scope"] = "local"
    }

    if (name != null) {
      values[name] = value
    }

    return values.takeIf { it.isNotEmpty() }
  }
}
