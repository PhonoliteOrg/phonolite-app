# Find the right test

| Directory | Purpose |
| --- | --- |
| [`../integration_test/`](../integration_test/README.md) | On-screen interaction inventory, feature journeys, and physical-device profile captures |
| [`ui_automation/`](ui_automation/) | Inventory/journey integrity, frame math, and host report correctness |
| [`audio_automation/`](audio_automation/) | Audio continuity/latency metric regressions, synthetic stalls and audio report correctness |
| [`widgets/`](widgets/) | Focused UI behavior, layout, input and navigation regression tests |
| [`entities/`](entities/) | Entity/authentication contracts |
| [`architecture/`](architecture/) | Controller, storage, audio, download and lifecycle behavior |
| [`platform/`](platform/) | Platform adapter behavior |
| [`requirements/`](requirements/) | Existing source/platform/requirements contracts |
| [`server_integration/`](server_integration/) | Opt-in live-server fixtures (`requires-server` tag) |
| [`support/`](support/) | Reusable host/widget fixtures |
| [`fixtures/`](fixtures/) | Shared fixture data |

The physical-device journeys are grouped by user-facing feature, separately from
host-only tests. They are opt-in via `flutter drive`; ordinary `flutter test`
does not launch an iPhone or run integration journeys. See the
[interaction inventory](../integration_test/catalog/INTERACTIONS.md) for the map
from visible action to device journey. Existing test files retain their paths.
