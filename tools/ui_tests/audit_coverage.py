#!/usr/bin/env python3
"""Aggregate successful device evidence, keeping fixtures and live runs distinct."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs', nargs='+', type=Path, help='Run directories or run.json paths')
    parser.add_argument('--output', type=Path, default=Path('build/ui-profile-audit'))
    args = parser.parse_args()
    catalog = [(feature['feature'], item)
               for path in sorted((ROOT / 'integration_test/catalog').glob('*.json'))
               for feature in [json.loads(path.read_text())]
               for item in feature['interactions']]
    evidence = {item['id']: {'live': [], 'fixture': []} for _, item in catalog}
    sources = []
    for path in args.runs:
        path = path / 'run.json' if path.is_dir() else path
        run = json.loads(path.read_text())
        # Preserve the distinction when reading reports from the removed
        # temporary-server suite; historical fixture results are not live runs.
        kind = 'fixture' if isinstance(run.get('isolated_fixture'), dict) else 'live'
        journeys = run.get('journeys', [])
        sources.append({'path': str(path), 'environment': kind,
                        'run_status': run.get('run_status'),
                        'passed': sum(j.get('status') == 'passed' for j in journeys),
                        'failed': sum(j.get('status') == 'failed' for j in journeys),
                        'skipped': sum(j.get('status') == 'skipped' for j in journeys)})
        for journey in journeys:
            if journey.get('status') != 'passed':
                continue
            interactions = list(journey.get('covered_interactions', []))
            legacy_playback = bool(run.get('control_suite')) and not interactions
            if legacy_playback:
                interactions = [item['id'] for _, item in catalog if journey['id'] in item.get('playback_journeys', [])]
            for interaction in interactions:
                if interaction in evidence:
                    evidence[interaction][kind].append({'run': str(path), 'journey': journey['id'],
                                                      'mapping': 'catalog.playback_journeys' if legacy_playback else 'recorded_interactions'})
    rows = []
    for feature in sorted({f for f, _ in catalog}):
        items = [i for f, i in catalog if f == feature]
        rows.append({'feature': feature, 'catalogued': len(items),
                     'live': sum(bool(evidence[i['id']]['live']) for i in items),
                     'fixture': sum(bool(evidence[i['id']]['fixture']) for i in items),
                     'either': sum(any(evidence[i['id']].values()) for i in items)})
    totals = {key: sum(row[key] for row in rows) for key in ['catalogued', 'live', 'fixture', 'either']}
    uncovered = [dict(feature=f, **i) for f, i in catalog if not any(evidence[i['id']].values())]
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'coverage_audit.json').write_text(json.dumps(
        {'totals': totals, 'sources': sources, 'features': rows, 'evidence': evidence, 'unexercised': uncovered}, indent=2) + '\n')
    lines = ['# Device interaction evidence', '',
             f"{totals['live']} patterns have live-device evidence; {totals['fixture']} have isolated on-device fixture evidence. "
             f"Their union is {totals['either']}/{totals['catalogued']} source-catalogued patterns.", '',
             'Only passed journeys count, including saved passes from interrupted runs. Legacy player-control reports use the explicit catalog playback mappings; other runs use recorded interaction IDs. A fixture pass does not certify the real server protocol. '
             'The catalog includes desktop, native, source-only and unwired controls. Counts do not establish every state or combination.', '',
             '| Feature | Live | Fixture | Either | Catalogued |',
             '| --- | ---: | ---: | ---: | ---: |']
    lines += [f"| {r['feature']} | {r['live']} | {r['fixture']} | {r['either']} | {r['catalogued']} |" for r in rows]
    lines += ['', '## Unexercised', '']
    lines += [f"- `{i['id']}` — {i['availability']}" for i in uncovered]
    lines += ['', '## Report sources', '']
    lines += [f"- `{s['path']}` ({s['environment']}; {s['passed']} passed, {s['failed']} failed, {s['skipped']} skipped; {s['run_status']})" for s in sources]
    (args.output / 'COVERAGE_AUDIT.md').write_text('\n'.join(lines) + '\n')
    print(json.dumps(totals))


if __name__ == '__main__':
    main()
