import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';

class DevicePickerModal extends StatefulWidget {
  const DevicePickerModal({
    super.key,
    required this.fetchDevices,
    required this.onSelected,
    required this.selectedId,
  });

  final Future<List<OutputDevice>> Function(bool refresh) fetchDevices;
  final Future<void> Function(OutputDevice device) onSelected;
  final int selectedId;

  @override
  State<DevicePickerModal> createState() => _DevicePickerModalState();
}

class _DevicePickerModalState extends State<DevicePickerModal> {
  List<OutputDevice> _devices = const [];
  bool _loading = true;
  String? _error;
  late final ScrollController _listController;

  @override
  void initState() {
    super.initState();
    _listController = ScrollController();
    _loadDevices(refresh: true);
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  Future<void> _loadDevices({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await widget.fetchDevices(refresh);
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        : _error != null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              )
            : Scrollbar(
                controller: _listController,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: _listController,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
                  itemCount: _devices.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: ObsidianPalette.textMuted.withOpacity(0.25),
                  ),
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final isSelected = device.id == widget.selectedId;
                    return ObsidianHoverRow(
                      onTap: () async {
                        await widget.onSelected(device);
                        if (!mounted) {
                          return;
                        }
                        Navigator.of(context).pop();
                      },
                      enabled: true,
                      isActive: isSelected,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    letterSpacing: 0.4,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          isSelected
                              ? const Icon(Icons.check_rounded,
                                  color: ObsidianPalette.gold)
                              : const SizedBox.shrink(),
                        ],
                      ),
                    );
                  },
                ),
              );

    return AlertDialog(
      title: const Text('Select output device'),
      content: SizedBox(width: 320, height: 360, child: content),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => _loadDevices(refresh: true),
          child: const Text('Refresh'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
