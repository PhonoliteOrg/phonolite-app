#!/usr/bin/env python3
"""Render the curated interaction inventory plus a reproducible handler index."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'integration_test/catalog'


def main():
    features = [json.loads(p.read_text()) for p in sorted(CATALOG.glob('*.json'))]
    count = sum(len(f['interactions']) for f in features)
    automated = sum(bool(i['journeys']) for f in features for i in f['interactions'])
    playback = sum(bool(i.get('playback_journeys')) for f in features for i in f['interactions'])
    lines = [
        '# On-screen interaction inventory', '',
        f'{count} source-audited interaction patterns across {len(features)} feature catalogs. '
        f'{automated} patterns have a device journey; that is implementation coverage, '
        'not proof that they ran on a phone.', '',
        f'{playback} patterns also link to the separate opt-in playback-changing suite. '
        'Run it with `bash tools/ui_tests/run_player_controls.sh DEVICE_ID`; '
        'those actions do not run in the ordinary UI suite.', '',
        'Each row is an interaction pattern, reused for every track/album/artist/playlist. '
        'Local/server, empty/populated, loading/disabled and compact/wide variations require '
        'their own device/data coverage. Native UI and source-only pages are explicitly marked. '
        'The inventory is source-audited, not a claim that every runtime state was visited.', '',
        'Edit the feature JSON files, implement journeys under `../journeys/`, then regenerate '
        'with `python3 tools/ui_tests/catalog.py` from the app directory. '
        'Run `flutter test test/ui_automation` to validate references.', '',
    ]
    for feature in features:
        lines += [f"## {feature['feature'].replace('_', ' ').title()}", '',
                  'Sources: ' + ', '.join(f'[{s}](../../{s})' for s in feature['sources']), '',
                  '| ID | Visible action | Expected outcome | Available when | Effect | Device journey |',
                  '| --- | --- | --- | --- | --- | --- |']
        for item in feature['interactions']:
            implemented = list(item['journeys'])
            implemented += ['Opt-in playback: ' + j for j in item.get('playback_journeys', [])]
            cells = [item['id'], item['action'], item['expected'], item['availability'],
                     item['risk'], ', '.join(implemented) or 'Pending / prerequisite-specific']
            lines.append('| ' + ' | '.join(str(c).replace('|', r'\|') for c in cells) + ' |')
        lines.append('')
    (CATALOG / 'INTERACTIONS.md').write_text('\n'.join(lines) + '\n')

    # This index is a review aid, not an assertion that a callback equals a unique
    # visible action. Reusable widgets and named callback parameters create duplicates.
    pattern = re.compile(
        r'\b(on(?:Tap\w*|Pressed|LongPress\w*|DoubleTap\w*|Changed|Submitted|'
        r'HorizontalDrag\w*|VerticalDrag\w*|Pan\w*|Dismiss\w*|Reorder|Scale\w*))\s*:'
    )
    index = ['# UI callback source index', '',
             'Candidate callback bindings in pages and widgets, including reusable wrappers. '
             'Use this to audit inventory gaps after UI changes. Entries are not test coverage.', '']
    total = 0
    for directory in ['lib/pages', 'lib/ui']:
        for path in sorted((ROOT / directory).rglob('*.dart')):
            matches = [(line, m.group(1)) for line, text in enumerate(path.read_text().splitlines(), 1)
                       for m in pattern.finditer(text) if not text.lstrip().startswith('//')]
            if not matches:
                continue
            relative = path.relative_to(ROOT).as_posix()
            index += [f'## {relative}', '']
            index += [f'- [{callback}, line {line}](../../{relative}#L{line})' for line, callback in matches]
            index.append('')
            total += len(matches)
    (CATALOG / 'SOURCE_INDEX.md').write_text('\n'.join(index) + '\n')
    print(f'{count} patterns; {automated} with journeys; {total} candidate callback bindings indexed.')


if __name__ == '__main__':
    main()
