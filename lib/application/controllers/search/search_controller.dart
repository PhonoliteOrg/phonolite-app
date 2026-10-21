import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';

class SearchController extends FeatureController {
  final AppController app;
  String _filter = 'all';

  SearchController(this.app);

  String get filter => _filter;

  void submit(String text) => app.search(text.trim(), filter: _filter);

  void clear() => app.search('', filter: _filter);

  void selectFilter(String value, String text) {
    update(() => _filter = value);

    if (text.trim().isNotEmpty) {
      submit(text);
    }
  }
}
