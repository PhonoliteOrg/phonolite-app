import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Counts live row animation controllers without exporting track/user data.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) throw ArgumentError('Expected VM websocket URI');
  final service = await vmServiceConnectUri(arguments.first);
  try {
    final vm = await service.getVM();
    final isolate = vm.isolates!.firstWhere((i) => i.name == 'main');
    await service.getAllocationProfile(isolate.id!, gc: true);
    final classes = await service.getClassList(isolate.id!);
    final row = classes.classes!.firstWhere(
      (c) => c.name == '_TrackRowTileState',
    );
    final instances = await service.getInstances(isolate.id!, row.id!, 1000);
    var mounted = 0, controllers = 0, playing = 0, idleControllers = 0;
    for (final ref in instances.instances!) {
      final state = await service.getObject(isolate.id!, ref.id!) as Instance;
      InstanceRef? field(String name) {
        final matches = state.fields!.where((f) => f.decl?.name == name);
        return matches.isEmpty ? null : matches.first.value as InstanceRef?;
      }

      final widgetRef = field('_widget');
      if (widgetRef == null || widgetRef.kind == InstanceKind.kNull) continue;
      mounted++;
      final widget =
          await service.getObject(isolate.id!, widgetRef.id!) as Instance;
      final active =
          widget.fields!.firstWhere((f) => f.decl?.name == 'isPlaying').value
              as InstanceRef;
      final isPlaying = active.valueAsString == 'true';
      if (isPlaying) playing++;
      final controller = field('_controller');
      if (controller != null && controller.kind != InstanceKind.kNull) {
        controllers++;
        if (!isPlaying) idleControllers++;
      }
    }
    final result = {
      'instances': instances.totalCount,
      'gc_before_inspection': true,
      'mounted_rows': mounted,
      'playing_rows': playing,
      'animation_controllers': controllers,
      'idle_row_controllers': idleControllers,
      'inspection_limit': 1000,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    stdout.writeln(jsonEncode(result));
    if (arguments.length > 1) {
      await File(arguments[1]).writeAsString(jsonEncode(result));
    }
  } finally {
    await service.dispose();
  }
}
