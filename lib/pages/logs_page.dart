import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../entities/app_log.dart';
import '../widgets/display/message_log.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/navigation/command_link_button.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<List<LogEntry>>(
      stream: controller.messageStream,
      initialData: controller.messages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommandLinkButton(
                label: 'Back to settings',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: MessageLog(
                  title: 'Logs',
                  subtitle: messages.isEmpty ? 'No events yet' : 'System log',
                  messages: messages,
                  onClear: controller.clearMessages,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
