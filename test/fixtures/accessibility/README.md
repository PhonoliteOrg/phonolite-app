# Native accessibility reparent regressions

These synthetic traces isolate the structural failure reported by Flutter's
Windows accessibility bridge. They contain node IDs and child lists only, with
no application content or captured user data.

Initially, node `3` belongs to node `1` and has child `31`. The second update moves
node `3` beneath node `2`. Flutter's bridge first removes node `3` from its old
parent, which deletes its native subtree, including node `31`.

- `missing_descendant.txt` omits unchanged node `31` from the second update. The
  installed native AXTree rejects it with `Nodes left pending by the update: 31`.
- `complete_descendant.txt` resends node `31` in that update and passes.

A cached final-graph check accepts both traces because it retains node `31` from
the first update. Regression checks must account for native subtree deletion
before applying the reparenting update.

The trace format uses `R` to reset a tree, followed by `B N` and `N` node records.
Each record is `id child_count child_ids...`. See
[`tools/accessibility`](../../../tools/accessibility/README.md) for native replay.

## Captured Windows startup

`windows_startup_reparent.txt` preserves the first six structural batches from
the reported Windows startup on October 30, 2026. It contains no UI text or field
values. The sixth batch replaces parent `29` with `62` and moves children `30`
and `31` beneath it. That batch resends node `30` but omits node `31`. Native
subtree removal deletes both children, so the main update leaves node `31`
uninitialized and produces the exact reported error.

`windows_startup_reparent_complete.txt` adds the previously captured empty node
`31` to the sixth batch. All six native updates then pass. This positive control
isolates the missing data; it is not an application or SDK patch.
