enum VehicleHomeAction { libraryShuffle, likedShuffle, customShuffle }

class VehicleItem {
  final String? id;
  final VehicleHomeAction? action;
  final String title;
  final String subtitle;
  final bool? enabled;
  final String? artworkUrl;
  final String? artworkPath;
  final int? sessionRevision;

  const VehicleItem({
    required String this.id,
    required this.title,
    required this.subtitle,
    this.enabled,
    this.artworkUrl,
    this.artworkPath,
    this.sessionRevision,
  }) : action = null;

  const VehicleItem.action({
    required VehicleHomeAction this.action,
    required this.title,
    required this.subtitle,
    required bool this.enabled,
  }) : id = null,
       artworkUrl = null,
       artworkPath = null,
       sessionRevision = null;
}
