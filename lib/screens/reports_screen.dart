import 'package:flutter/material.dart';
import 'history_screen.dart';
import 'reports/reports_summary_tab.dart';

/// GlobalKey tab Transaksi — tap legenda donut lompat ke tab Transaksi
/// dengan filter kategori terisi (dipanggil lintas _ReportsSummaryTab).
final summaryToHistoryKey = GlobalKey<HistoryTabState>();

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Laporan'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Ringkasan'), Tab(text: 'Transaksi')],
          ),
        ),
        body: TabBarView(
          children: [
            const ReportsSummaryTab(),
            HistoryTab(key: summaryToHistoryKey),
          ],
        ),
      ),
    );
  }
}
