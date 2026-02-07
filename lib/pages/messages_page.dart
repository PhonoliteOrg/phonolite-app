import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../widgets/display/message_log.dart';
import '../widgets/layouts/app_scope.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<List<String>>(
      stream: controller.messageStream,
      initialData: controller.messages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        return Padding(
          padding: const EdgeInsets.all(20),
          child: MessageLog(
            messages: messages,
            onClear: controller.clearMessages,
          ),
        );
      },
    );
  }
}
