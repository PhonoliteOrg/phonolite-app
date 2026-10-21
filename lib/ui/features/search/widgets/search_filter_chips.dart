import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';

class SearchFilterChips extends StatelessWidget {
  final String activeFilter;
  final ValueChanged<String> onChanged;

  const SearchFilterChips({super.key, required this.activeFilter, required this.onChanged});

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
              avatar: activeFilter == filter ? const Icon(PhonoliteIcons.check, size: 18) : null,
              onSelected: withSelectionHaptic((_) => onChanged(filter)),
            ),
          )
          .toList(),
    );
  }
}
