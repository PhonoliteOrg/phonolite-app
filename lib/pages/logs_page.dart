import 'package:flutter/material.dart';

import '../entities/app_log.dart';
import '../widgets/display/message_log.dart';
import '../widgets/inputs/obsidian_toggle_option.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/layouts/playback_content_inset.dart';
import '../widgets/navigation/command_link_button.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  static const routeName = '/settings/logs';

  static Route<void> route() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const LogsPage(),
    );
  }

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  LogCategory _category = LogCategory.all;
  List<LogEntry>? _lastMessages;
  LogCategory? _lastCategory;
  List<LogEntry> _filtered = const [];

  List<LogEntry> _filter(List<LogEntry> messages) {
    if (!identical(_lastMessages, messages) || _lastCategory != _category) {
      _lastMessages = messages;
      _lastCategory = _category;
      _filtered = _category == LogCategory.all
          ? messages
          : messages
                .where((entry) => entry.categories.contains(_category))
                .toList(growable: false);
    }
    return _filtered;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<LogEntry>>(
          stream: controller.messageStream,
          initialData: controller.messages,
          builder: (context, snapshot) {
            final messages = _filter(snapshot.data ?? const <LogEntry>[]);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20 + PlaybackContentInset.topOf(context),
                20,
                20 + PlaybackContentInset.bottomOf(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CommandLinkButton(
                    label: 'Back to settings',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (final category in LogCategory.values)
                          ObsidianToggleOption(
                            label: category.label,
                            isActive: _category == category,
                            onPressed: () {
                              if (_category != category) {
                                setState(() => _category = category);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: MessageLog(
                      key: ValueKey(_category),
                      title: 'Logs',
                      messages: messages,
                      onClear: controller.clearMessages,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
