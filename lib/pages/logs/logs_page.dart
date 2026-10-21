import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/logs/logs_controller.dart';
import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/logs/widgets/message_log.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_toggle_option.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';

class LogsPage extends BasePage {
  static const String routeName = '/settings/logs';

  const LogsPage({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const LogsPage(),
    );
  }

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends BasePageState<LogsPage> {
  late final LogsController _feature = bindController(LogsController());

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  PageToolbarPlacement get toolbarPlacement => PageToolbarPlacement.fixed;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.fromLTRB(20, 20, 20, 12);

  void _selectCategory(LogCategory category) {
    if (_feature.category != category) {
      _feature.selectCategory(category);
    }
  }

  Widget _categoryFilters() => Center(
    child: Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final category in LogCategory.values)
          ObsidianToggleOption(
            label: category.label,
            isActive: _feature.category == category,
            onPressed: () => _selectCategory(category),
          ),
      ],
    ),
  );

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);

    return StreamBuilder<List<LogEntry>>(
      stream: controller.messageStream,
      initialData: controller.messages,
      builder: (context, snapshot) {
        final messages = _feature.filter(snapshot.data ?? const <LogEntry>[]);

        return assemble(
          context,
          navbar: DetailActionHeader(backLabel: 'Back to settings', onBack: () => Navigator.of(context).pop()),
          body: PageBody.box(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            includePlaybackInsets: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _categoryFilters(),
                const SizedBox(height: 8),
                Expanded(
                  child: MessageLog(
                    key: ValueKey(_feature.category),
                    title: 'Logs',
                    messages: messages,
                    onClear: controller.clearMessages,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
