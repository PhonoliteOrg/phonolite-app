import 'dart:async';

import 'package:phonolite_app/data/models/collections/playlist.dart';

typedef PlaylistEditorSubmit =
    FutureOr<void> Function(String name, String description, PlaylistImageEdit imageEdit, PlaylistEditorTarget target);

enum PlaylistEditorTarget { local, server }
