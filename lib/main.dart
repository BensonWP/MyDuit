import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/bills_screen.dart';
import 'screens/profil_screen.dart';
import 'screens/transaction_form_screen.dart';
import 'providers/database_provider.dart';
import 'services/brand_logo_backfill.dart';
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
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [
      privacyModeProvider
          .overrideWith((_) => prefs.getBool(privacyModePrefKey) ?? false),
    ],
    child: const MyApp(),
  ));
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
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Splash padat 1400ms: lead-in 100 + zoom 450 + wobble 350 + shimmer 450.
  static const _hold = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    // Sekali: isi logo brand bawaan dari asset → blob DB (idempotent).
    unawaited(backfillBuiltinBrandLogos(ref.read(dbProvider)));
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
    final reduced = MediaQuery.of(context).disableAnimations;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration:
            reduced ? Duration.zero : const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const LockGate(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
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
                // Lead-in 100ms: frame jank awal (startup) tidak memakan
                // zoom-punch pertama.
                .animate(delay: 100.ms)
                // Zoom-punch: blur besar → tajam, overshoot sedikit.
                .fadeIn(duration: 250.ms)
                .scale(
                  begin: const Offset(2.6, 2.6),
                  end: const Offset(1, 1),
                  duration: 450.ms,
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
                .then()
                .shake(duration: 350.ms, hz: 2.4, rotation: pi / 60)
                // Kilap terakhir sebelum masuk app.
                .then()
                .shimmer(duration: 450.ms, color: Colors.white),
      ),
    );
  }
}

/// Gerbang kunci biometrik: membungkus MainShell. State shell tetap hidup
/// di Offstage saat terkunci — PageView & data tidak di-reset.
/// Kebijakan: terkunci saat dibuka, dan saat kembali dari background
/// setelah lebih dari [LockService.graceDuration].
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key});

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _locked = false;

  /// Fase keluar sinematik: layar kunci fade + zoom sebelum dilepas.
  bool _unlocking = false;
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
        backgroundedAt: _backgroundedAt,
      );
      _backgroundedAt = null;
      if (lockNow && !_locked) setState(() => _locked = true);
    }
  }

  void _unlock() => _cinematicUnlock();

  /// Sukses biometrik: layar kunci fade + zoom out 280ms, baru dilepas —
  /// sinematik, bukan cut instan. Lalu bump nonce agar Beranda replay
  /// entrance-nya tepat saat tirai tersingkap.
  Future<void> _cinematicUnlock() async {
    if (_unlocking || !_locked) return;
    final reduced = MediaQuery.of(context).disableAnimations;
    setState(() => _unlocking = true);
    await Future.delayed(
        reduced ? Duration.zero : const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() {
      _locked = false;
      _unlocking = false;
    });
    ref.read(unlockNonceProvider.notifier).state++;
  }

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
    final reduced = MediaQuery.of(context).disableAnimations;
    final exitDuration =
        reduced ? Duration.zero : const Duration(milliseconds: 280);
    return Stack(
      children: [
        const MainShell(),
        // LockScreen hanya ada di tree saat terkunci → initState-nya
        // (auto-prompt biometrik) baru berjalan saat benar-benar terkunci.
        // Fase _unlocking: fade + zoom sebelum dilepas dari tree.
        if (_locked)
          AnimatedScale(
            scale: _unlocking ? 1.06 : 1.0,
            duration: exitDuration,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _unlocking ? 0.0 : 1.0,
              duration: exitDuration,
              child: LockScreen(onUnlock: _unlock),
            ),
          ),
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

  // Pemutus loop onPageChanged → navIndexProvider → animateToPage: tanpa ini,
  // lompatan multi-tab memicu onPageChanged di tab antara (mis. Wallet saat
  // Beranda → Tagihan) yang memanggil animateToPage lagi dan menghijack
  // animasi — halaman mendarat di tengah jalan.
  bool _navAnimating = false;
  // Penanda sinkron bahwa penulisan navIndex berasal dari PageView (swipe):
  // halaman sudah bergerak sendiri, listener tidak boleh menganimasikan ulang
  // (akan melawan drag yang sedang berjalan).
  bool _swiping = false;

  void _animateToPage(int page) {
    // ponytail: tap beruntun di tengah animasi di-snap langsung;
    // antrekan animasinya bila snap terasa kasar.
    if (_navAnimating) {
      _pageController.jumpToPage(page);
      return;
    }
    _navAnimating = true;
    _pageController
        .animateToPage(
          page,
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _navAnimating = false)
        .ignore();
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(activeBillsDetailedProvider, (prev, next) {
      final rows = next.valueOrNull;
      if (rows != null) {
        unawaited(NotificationService.instance
            .rescheduleAll([for (final r in rows) r.bill]));
      }
    }, fireImmediately: true);
    ref.listenManual(navIndexProvider, (prev, next) {
      if (_swiping) return; // asal PageView: halaman sudah bergerak sendiri
      _animateToPage(next);
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
        onPageChanged: (i) {
          if (_navAnimating) return; // tab antara saat lompatan programatik
          _swiping = true; // set/reset sinkron: listener Riverpod sinkron
          try {
            ref.read(navIndexProvider.notifier).state = i;
          } finally {
            _swiping = false;
          }
        },
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
            label: 'Dompet',
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
