import 'package:flutter/widgets.dart';

/// Keeps source sections and their widget state together when their order changes.
List<Widget> orderedSourceSlivers({
  required bool localFirst,
  required List<Widget> localSlivers,
  required List<Widget> serverSlivers,
}) {
  final local = SliverMainAxisGroup(key: const ValueKey('local-source-sections'), slivers: localSlivers);
  final server = SliverMainAxisGroup(key: const ValueKey('server-source-sections'), slivers: serverSlivers);

  return localFirst ? [local, if (serverSlivers.isNotEmpty) server] : [if (serverSlivers.isNotEmpty) server, local];
}
