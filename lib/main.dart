import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/bills_screen.dart';
import 'screens/profil_screen.dart';
import 'screens/transaction_form_screen.dart';
import 'providers/database_provider.dart';
import 'services/lock_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  Intl.defaultLocale = 'id_ID';
  // Non-blocking: izin & channel siap sebelum UI, jadwal di-reschedule
  // oleh listener tagihan (lihat MainShell).
  unawaited(NotificationService.instance.init());
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyDuit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashScreen(),
    );
  }
}

/// Sambungan dari native splash ke app: logo zoom-punch (blur+overshoot),
/// mendarat dengan wobble, sapuan shimmer, lalu pushReplacement ke MainShell.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _hold = Duration(milliseconds: 2200);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final reduced = MediaQuery.of(context).disableAnimations;
      // Cold start selalu menampilkan logo sebentar; tanpa gerak bila
      // pengguna mematikan animasi sistem.
      Future.delayed(
          reduced ? const Duration(milliseconds: 600) : _hold, _go);
    });
  }

  void _go() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LockGate()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    final logo = Image.asset('assets/branding/app_logo.png', width: 190);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: reduced
            ? logo
            : logo
                // Lead-in 200ms: frame jank awal (startup) tidak memakan
                // zoom-punch pertama.
                .animate(delay: 200.ms)
                // Zoom-punch: blur besar → tajam, overshoot sedikit.
                .fadeIn(duration: 250.ms)
                .scale(
                  begin: const Offset(2.6, 2.6),
                  end: const Offset(1, 1),
                  duration: 650.ms,
                  curve: Curves.easeOutBack,
                  delay: 0.ms,
                )
                .blur(
                  begin: const Offset(10, 10),
                  end: Offset.zero,
                  duration: 400.ms,
                  delay: 0.ms,
                )
                // Mendarat: wobble kecil.
                .then(delay: 80.ms)
                .shake(duration: 450.ms, hz: 2.4, rotation: pi / 60)
                // Kilap terakhir sebelum masuk app.
                .then()
                .shimmer(duration: 650.ms, color: Colors.white),
      ),
    );
  }
}

/// Gerbang kunci biometrik: membungkus MainShell. State shell tetap hidup
/// di Offstage saat terkunci — PageView & data tidak di-reset.
/// Kebijakan: terkunci saat dibuka, dan saat kembali dari background
/// setelah lebih dari [LockService.graceDuration].
class LockGate extends StatefulWidget {
  const LockGate({super.key});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _checking = true;
  bool _locked = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLock();
  }

  Future<void> _initLock() async {
    final enabled = await LockService.isEnabled();
    if (!mounted) return;
    setState(() {
      _locked = enabled; // dibuka → langsung terkunci jika fitur nyala
      _checking = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_checking) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final lockNow = LockService.shouldLock(
        enabled: _locked,
        firstResume: false,
        backgroundedAt: _backgroundedAt,
      );
      _backgroundedAt = null;
      if (lockNow && !_locked) setState(() => _locked = true);
    }
  }

  void _unlock() => setState(() => _locked = false);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Stack(
      children: [
        const MainShell(),
        // LockScreen hanya ada di tree saat terkunci → initState-nya
        // (auto-prompt biometrik) baru berjalan saat benar-benar terkunci.
        if (_locked) LockScreen(onUnlock: _unlock),
      ],
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    ref.listenManual(activeBillsStreamProvider, (prev, next) {
      final bills = next.valueOrNull;
      if (bills != null) {
        unawaited(NotificationService.instance.rescheduleAll(bills));
      }
    }, fireImmediately: true);
    ref.listenManual(navIndexProvider, (prev, next) {
      _pageController.animateToPage(
        next,
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  static const _screens = [
    KeyedSubtree(key: ValueKey('home'), child: HomeScreen()),
    KeyedSubtree(key: ValueKey('reports'), child: ReportsScreen()),
    KeyedSubtree(key: ValueKey('accounts'), child: AccountsScreen()),
    KeyedSubtree(key: ValueKey('bills'), child: BillsScreen()),
    KeyedSubtree(key: ValueKey('profil'), child: ProfilScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navIndexProvider);
    final showFab = index < 2;

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => ref.read(navIndexProvider.notifier).state = i,
        children: _screens,
      ),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: () => TransactionForm.showAddSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(navIndexProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.insert_chart_outlined_rounded),
            selectedIcon: Icon(Icons.insert_chart_rounded),
            label: 'Laporan',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Tagihan',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
