import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/download_settings_controller.dart';
import 'package:phonolite_app/ui/features/settings/widgets/download_quality_selection.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/page_scroll_view.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';

class DownloadQualityPage extends BasePage {
  static const String routeName = '/settings/download-quality';

  final DownloadSettingsController? controller;

  const DownloadQualityPage({super.key, this.controller});

  static Route<void> route({DownloadSettingsController? controller}) => MaterialPageRoute<void>(
    settings: const RouteSettings(name: routeName),
    builder: (_) => DownloadQualityPage(controller: controller),
  );

  @override
  State<DownloadQualityPage> createState() => _DownloadQualityPageState();
}

class _DownloadQualityPageState extends BasePageState<DownloadQualityPage> {
  DownloadSettingsController get _controller => widget.controller ?? DownloadSettingsController.instance;

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
    } catch (_) {
      // The controller exposes a recoverable error on this page.
    }
  }

  Future<void> _retry() async {
    try {
      await _controller.retryInitialization();
    } catch (_) {
      // Keep the last error visible if device storage is still unavailable.
    }
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => assemble(
      context,
      navbar: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailActionHeader(backLabel: 'Back to settings', onBack: () => Navigator.of(context).pop()),
          const SizedBox(height: 16),
          const LibraryHeader(title: 'DOWNLOAD QUALITY', maxLines: 2),
        ],
      ),
      body: PageBody.slivers(
        slivers: [
          PageSliverBox(
            top: 8,
            bottom: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose how much space downloaded music uses on this device.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                DownloadQualitySelection(
                  quality: _controller.settings.quality,
                  enabled: _controller.ready,
                  onSelected: (quality) => unawaited(_controller.setQuality(quality)),
                ),
                const SizedBox(height: 20),
                Text(
                  'Applies to future downloads. Existing downloads keep their current quality.\n\n'
                  'Storage estimates exclude artwork and metadata. Actual sizes vary. '
                  'Original preserves the source file; it is lossless only when the source is lossless.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
                ),
                if (_controller.saving) ...[const SizedBox(height: 12), const Text('Saving preference…')],
                if (_controller.error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (!_controller.ready)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TechButton(label: 'Retry', onTap: () => unawaited(_retry())),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
