import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shell/playback_content_inset.dart';

/// Keeps the last row scrollable above the playbar without shrinking the view.
class SliverPlaybackInset extends StatelessWidget {
  const SliverPlaybackInset({super.key});

  @override
  Widget build(BuildContext context) =>
      SliverToBoxAdapter(child: SizedBox(height: PlaybackContentInset.bottomOf(context)));
}
