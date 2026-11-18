import 'package:flutter/material.dart';

class ArtistReleaseHeading extends StatelessWidget {
  final String title;
  final int count;

  const ArtistReleaseHeading({super.key, required this.title, required this.count});

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
    sliver: SliverToBoxAdapter(child: Text('$title ($count)', style: Theme.of(context).textTheme.titleLarge)),
  );
}
