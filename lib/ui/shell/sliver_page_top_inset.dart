import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shell/playback_content_inset.dart';

/// Starts content below the status bar while letting it scroll behind it.
class SliverPageTopInset extends StatelessWidget {
  /// Keeps later pinned controls below system UI without clipping the viewport.
  final bool pinned;

  const SliverPageTopInset({super.key, this.pinned = false});

  @override
  Widget build(BuildContext context) {
    final spacer = SizedBox(height: PlaybackContentInset.topOf(context));

    return pinned ? PinnedHeaderSliver(child: spacer) : SliverToBoxAdapter(child: spacer);
  }
}
