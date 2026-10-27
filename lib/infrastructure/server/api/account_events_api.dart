import 'package:phonolite_app/data/models/collections/account_collection_event.dart';
import 'package:phonolite_app/data/models/collections/account_collection_snapshot.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/sse_transport.dart';

class AccountEventsApi extends JsonApiEndpoint {
  final SseTransport _events;

  AccountEventsApi(super.transport) : _events = SseTransport(transport);

  Stream<AccountCollectionEvent> streamCollectionEvents() =>
      _events.openJson(path: '/account/collections/events', decode: AccountCollectionEvent.tryFromJson);

  Future<AccountCollectionSnapshot> fetchCollectionSnapshot() =>
      getValue('/account/collections/snapshot', AccountCollectionSnapshot.fromJson);
}
