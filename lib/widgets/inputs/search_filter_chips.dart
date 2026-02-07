import 'package:flutter/material.dart';

class SearchFilterChips extends StatelessWidget {
  const SearchFilterChips({
    super.key,
    required this.activeFilter,
    required this.onChanged,
  });

  final String activeFilter;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const filters = ['artist', 'album', 'track'];
    return Wrap(
      spacing: 8,
      children: filters
          .map(
            (filter) => ChoiceChip(
              label: Text(filter.toUpperCase()),
              selected: activeFilter == filter,
              onSelected: (_) => onChanged(filter),
            ),
          )
          .toList(),
    );
  }
}
