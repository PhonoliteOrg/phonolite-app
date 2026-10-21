import 'dart:collection';

/// Functional selection policy composed by feature controllers.
///
/// The owning controller supplies its state-change boundary so selecting across
/// several groups still produces one synchronous notification. Groups preserve
/// separate identities, such as the local and server liked-track selections.
class ControllerSelection<K> {
  final void Function(void Function()) _update;
  final Map<String, Set<K>> _groups;
  bool _active = false;

  ControllerSelection(
    this._update, {
    Iterable<String> groups = const ['default'],
    Map<String, Iterable<K>> initialValues = const {},
  }) : _groups = {
         for (final group in groups) group: {...?initialValues[group]},
       };

  bool get active => _active;

  /// A read-only live view; mutation stays inside the shared notification boundary.
  Set<K> keys([String group = 'default']) => UnmodifiableSetView(_groups[group]!);

  void setActive(bool value) {
    if (_active != value) {
      _update(() => _active = value);
    }
  }

  void toggle(K key, {String group = 'default', bool? activate = true}) {
    void toggleSelectedKey() {
      if (activate != null) {
        _active = activate;
      }

      final selected = _groups[group]!;

      if (!selected.remove(key)) {
        selected.add(key);
      }
    }

    _update(toggleSelectedKey);
  }

  void enter(K key, {String group = 'default'}) {
    void enterSelection() {
      _active = true;
      _groups[group]!.add(key);
    }

    _update(enterSelection);
  }

  void replace(Iterable<K> values, {bool? activate = true}) => replaceGroups({'default': values}, activate: activate);

  void replaceGroups(Map<String, Iterable<K>> values, {bool? activate = true}) {
    // Materialize first: callers may replace a group with its own lazy view.
    final replacements = {for (final entry in values.entries) entry.key: entry.value.toSet()};

    void replaceSelectedGroups() {
      if (activate != null) {
        _active = activate;
      }

      for (final entry in replacements.entries) {
        final selected = _groups[entry.key]!;

        selected.clear();
        selected.addAll(entry.value);
      }
    }

    _update(replaceSelectedGroups);
  }

  void removeKeys(Iterable<K> values, {String group = 'default', bool? activate}) {
    final removed = values.toSet();

    void removeSelectedKeys() {
      _groups[group]!.removeAll(removed);

      if (activate != null) {
        _active = activate;
      }
    }

    _update(removeSelectedKeys);
  }

  void clear({bool? activate = false}) {
    void clearSelectedGroups() {
      if (activate != null) {
        _active = activate;
      }

      for (final selected in _groups.values) {
        selected.clear();
      }
    }

    _update(clearSelectedGroups);
  }
}
