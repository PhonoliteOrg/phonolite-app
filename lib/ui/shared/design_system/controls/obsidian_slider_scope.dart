import 'package:flutter/material.dart';

/// Keeps a slider's floating nodes inside its own visibility and clipping scope.
/// This prevents detached accessibility updates during route and sheet startup.
class ObsidianSliderScope extends StatelessWidget {
  final Slider child;

  const ObsidianSliderScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Overlay.wrap(
      // Preserve the slider's preferred height while allowing its value popup
      // to paint beyond the track without escaping the surrounding route.
      clipBehavior: Clip.none,
      // Flutter changes the slider's internal Focus semantics when enabledness
      // changes. Recreate its portal then so native clients receive a full tree.
      child: KeyedSubtree(key: ValueKey(child.onChanged != null), child: child),
    ),
  );
}
