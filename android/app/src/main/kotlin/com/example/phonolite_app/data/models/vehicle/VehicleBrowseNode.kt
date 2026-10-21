package com.example.phonolite_app.data.models.vehicle

sealed interface VehicleBrowseNode {
  data class Source(val scope: VehicleScope) : VehicleBrowseNode

  data class Category(val kind: VehicleCategory, val scope: VehicleScope) : VehicleBrowseNode

  data class Entry(val entry: VehicleEntry, val kind: VehicleCategory, val scope: VehicleScope) : VehicleBrowseNode

  data class Message(val kind: VehicleMessageKind, val category: VehicleCategory? = null, val error: String? = null) :
    VehicleBrowseNode
}
