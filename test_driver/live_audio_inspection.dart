/// Read-only VM inspection of the production worker's current encoded segment.
/// No evaluation, PCM capture or production instrumentation is needed.
Future<Map<String, Object?>> inspectLiveAudio(dynamic service) async {
  final dynamic vm = await service.getVM();
  for (final dynamic isolate in vm.isolates) {
    final dynamic classes = await service.getClassList(isolate.id);
    final engines = (classes.classes as List).where(
      (dynamic c) => c.name == '_AudioWorkerEngine',
    );
    if (engines.isEmpty) continue;
    final dynamic instances = await service.getInstances(
      isolate.id,
      engines.first.id,
      4,
    );
    for (final dynamic reference in instances.instances) {
      Future<dynamic> field(dynamic owner, String name) async {
        final dynamic object = await service.getObject(isolate.id, owner.id);
        return (object.fields as List)
            .firstWhere((dynamic f) => f.decl.name == name)
            .value;
      }

      final dynamic session = await field(reference, '_session');
      if (session.kind == 'Null') continue;
      final dynamic segment = await field(session, '_incomingSegment');
      if (segment.kind == 'Null') continue;
      final dynamic header = await field(segment, 'header');
      final dynamic object = await service.getObject(isolate.id, header.id);
      final values = <String, Object?>{};
      for (final dynamic f in object.fields) {
        values[f.decl.name as String] = int.tryParse(
          f.value.valueAsString ?? '',
        );
      }
      final dynamic packets = await field(segment, 'packets');
      final dynamic list = await service.getObject(
        isolate.id,
        packets.id,
        offset: 0,
        count: 100,
      );
      var payloadBytes = 0;
      var count = 0;
      for (final dynamic packet in list.elements ?? []) {
        final dynamic bytes = await service.getObject(
          isolate.id,
          packet.id,
          offset: 0,
          count: 0,
        );
        payloadBytes += (bytes.length as int?) ?? 0;
        count++;
      }
      return {
        'same_connection_as_playback': true,
        'header': values,
        'sampled_packet_count': count,
        'sampled_payload_bytes': payloadBytes,
        'encoded_payload_kbps': count == 0
            ? null
            : payloadBytes * 8 / (count * (values['frameMs'] as int)),
        'isolate_name': isolate.name,
      };
    }
  }
  return {'available': false};
}
