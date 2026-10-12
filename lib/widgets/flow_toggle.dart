import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/database_provider.dart';

/// Pilihan arus kartu tren (dipakai Beranda & Laporan).
/// null = filter OFF — klik segmen aktif lagi untuk mematikan.
class FlowToggle extends ConsumerWidget {
  const FlowToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final out = ref.watch(flowOutProvider);
    return SegmentedButton<bool>(
      selected: {if (out != null) out},
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      segments: const [
        ButtonSegment(value: true, label: Text('Keluar')),
        ButtonSegment(value: false, label: Text('Masuk')),
      ],
      // Segmen aktif diklik lagi → selection kosong → filter OFF.
      onSelectionChanged: (s) =>
          ref.read(flowOutProvider.notifier).state = s.isEmpty ? null : s.first,
    );
  }
}
