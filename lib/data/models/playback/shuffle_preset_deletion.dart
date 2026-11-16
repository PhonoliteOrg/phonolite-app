import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';

/// A selection of saved shuffles captured before the user confirms their deletion.
///
/// [sessionRevision] identifies the server session the selection belongs to; deleting
/// after that session has changed would act on another account's presets.
class ShufflePresetDeletion {
  final List<ShufflePreset> presets;
  final int sessionRevision;

  const ShufflePresetDeletion({required this.presets, required this.sessionRevision});
}
