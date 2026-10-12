import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../entities/app_log.dart';
import '../widgets/display/message_log.dart';
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
    final logger = AppLogger.instance;
    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: StreamBuilder<List<LogEntry>>(
          stream: controller.messageStream,
          initialData: controller.messages,
          builder: (context, snapshot) {
            final messages = _filter(snapshot.data ?? const <LogEntry>[]);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
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
                  SelectableText(
                    logger.persistenceError != null
                        ? 'Unable to save local logs: ${logger.persistenceError}'
                        : logger.storageDirectory == null
                        ? 'Local log files are unavailable.'
                        : 'Log folder: ${logger.storageDirectory}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<LogCategory>(
                        value: _category,
                        items: [
                          for (final category in LogCategory.values)
                            DropdownMenuItem(
                              value: category,
                              child: Text(category.label),
                            ),
                        ],
                        onChanged: (category) {
                          if (category != null) {
                            setState(() => _category = category);
                          }
                        },
                      ),
                      const Text('Newest 3,000 entries per file'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: MessageLog(
                      key: ValueKey(_category),
                      title: 'Logs',
                      subtitle: messages.isEmpty
                          ? 'No events yet'
                          : '${_category.fileName} • ${messages.length} entries',
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
