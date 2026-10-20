import 'package:flutter/material.dart';

import '../ui/phonolite_icons.dart';
import '../ui/button_haptics.dart';

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
              showCheckmark: false,
              avatar: activeFilter == filter
                  ? const Icon(PhonoliteIcons.check, size: 18)
                  : null,
              onSelected: withSelectionHaptic((_) => onChanged(filter)),
            ),
          )
          .toList(),
    );
  }
}
