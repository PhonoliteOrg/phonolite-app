import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';

class LogsController extends FeatureController {
  LogCategory _category = LogCategory.all;
  List<LogEntry>? _lastMessages;
  LogCategory? _lastCategory;
  List<LogEntry> _filtered = const [];

  LogCategory get category => _category;

  void selectCategory(LogCategory value) => update(() => _category = value);

  List<LogEntry> filter(List<LogEntry> messages) {
    if (!identical(_lastMessages, messages) || _lastCategory != _category) {
      _lastMessages = messages;
      _lastCategory = _category;
      _filtered = _category == LogCategory.all
          ? messages
          : messages.where((entry) => entry.categories.contains(_category)).toList(growable: false);
    }

    return _filtered;
  }
}
