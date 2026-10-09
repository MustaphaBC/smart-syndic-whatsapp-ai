import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'app_theme.dart';
import 'login_page.dart';
import 'history_page.dart';
import 'residence_selection.dart';
import 'analytics_page.dart';
import 'account_page.dart';
import 'api_service.dart';

// ignore: constant_identifier_names
const String BASE_URL = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://YOUR_BACKEND_HOST',
);

// ── Global theme notifier ─────────────────────────────────────────────────────
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.light);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SyndicApp());
}

class SyndicApp extends StatelessWidget {
  const SyndicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (_, mode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Syndic AI',
        themeMode: mode,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const AppInitializer(),
      ),
    );
  }
}

// ── App Initializer ───────────────────────────────────────────────────────────
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});
  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initApp();
  }

  Future<void> _initApp() async {
    await Firebase.initializeApp();
    _initFCM();
  }

  Future<void> _initFCM() async {
    try {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
      final messaging = FirebaseMessaging.instance;

      await messaging
          .requestPermission(alert: true, badge: true, sound: true)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              return const NotificationSettings(
                authorizationStatus: AuthorizationStatus.notDetermined,
                alert: AppleNotificationSetting.notSupported,
                announcement: AppleNotificationSetting.notSupported,
                badge: AppleNotificationSetting.notSupported,
                carPlay: AppleNotificationSetting.notSupported,
                lockScreen: AppleNotificationSetting.notSupported,
                notificationCenter: AppleNotificationSetting.notSupported,
                showPreviews: AppleShowPreviewSetting.notSupported,
                timeSensitive: AppleNotificationSetting.notSupported,
                criticalAlert: AppleNotificationSetting.notSupported,
                sound: AppleNotificationSetting.notSupported,
                providesAppNotificationSettings:
                    AppleNotificationSetting.notSupported,
              );
            },
          );

      await messaging
          .subscribeToTopic("admin_alerts")
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      const AndroidInitializationSettings initAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await flutterLocalNotificationsPlugin.initialize(
        const InitializationSettings(android: initAndroid),
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification != null) {
          flutterLocalNotificationsPlugin.show(
            message.hashCode,
            message.notification!.title,
            message.notification!.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'high_importance_channel',
                'Alertes Critiques',
                importance: Importance.max,
                priority: Priority.high,
                color: Color(0xFF3D5AFE),
              ),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint("⚠️ FCM init échoué (non bloquant): $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 60),
                  const SizedBox(height: 16),
                  Text(
                    'Erreur: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _initFuture = _initApp()),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return const AuthGate();
        }
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  'Démarrage de Syndic IA...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Auth Gate ─────────────────────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) return const DashboardPage();
        return const LoginPage();
      },
    );
  }
}

// ── Dashboard ─────────────────────────────────────────────────────────────────
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _pendingCount = 0;
  int _p0Count = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchPendingCount();
    // Refresh badge toutes les 30 secondes
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchPendingCount();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchPendingCount() async {
    try {
      final data = await ApiService.get('/api/pending-count');
      if (mounted) {
        setState(() {
          _pendingCount = (data['count'] as int?) ?? 0;
          _p0Count = (data['p0'] as int?) ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Pending count error: $e');
    }
  }

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Syndic IA'),
        actions: [
          // ── Dark mode toggle ──────────────────────────────────────────
          ValueListenableBuilder<ThemeMode>(
            valueListenable: appThemeMode,
            builder: (_, mode, _) => IconButton(
              icon: Icon(
                mode == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
              tooltip: mode == ThemeMode.dark ? 'Mode clair' : 'Mode sombre',
              onPressed: () {
                appThemeMode.value = mode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountPage()),
            ),
            tooltip: 'Mon compte',
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app_rounded),
            onPressed: () => _signOut(context),
            tooltip: 'Déconnexion',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Welcome header ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary,
                      scheme.primary.withBlue(
                        ((scheme.primary.b * 255.0).round() + 40).clamp(0, 255),
                      ),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.security_rounded,
                      size: 42,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AccountPage(),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bienvenue',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              user?.displayName ??
                                  user?.email?.split('@').first ??
                                  'Admin',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Voir mon profil →',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Alert badge P0
                    if (_p0Count > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_p0Count P0',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              Text(
                'MENU PRINCIPAL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 14),

              // ── Menu Grid ───────────────────────────────────────────────
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.1,
                children: [
                  // Supervision with badge
                  _DashCard(
                    icon: Icons.apartment_rounded,
                    label: 'Supervision',
                    sublabel: _pendingCount > 0
                        ? '$_pendingCount en attente'
                        : 'Tout est calme ✓',
                    color: scheme.primary,
                    badgeCount: _pendingCount,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ResidenceSelectionPage(
                            targetRoute: 'dashboard',
                          ),
                        ),
                      );
                      _fetchPendingCount(); // refresh badge on return
                    },
                  ),
                  _DashCard(
                    icon: Icons.people_rounded,
                    label: 'Résidents',
                    sublabel: 'Gérer les accès',
                    color: const Color(0xFF0288D1),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ResidenceSelectionPage(
                          targetRoute: 'residents',
                        ),
                      ),
                    ),
                  ),
                  _DashCard(
                    icon: Icons.history_rounded,
                    label: 'Historique',
                    sublabel: 'Tous les tickets',
                    color: const Color(0xFF00897B),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryPage()),
                    ),
                  ),
                  _DashCard(
                    icon: Icons.analytics_rounded,
                    label: 'Analytique',
                    sublabel: 'KPIs & rapports',
                    color: const Color(0xFF6A1B9A),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AnalyticsPage()),
                    ),
                  ),
                  _DashCard(
                    icon: Icons.manage_accounts_rounded,
                    label: 'Mon Compte',
                    sublabel: 'Profil & sécurité',
                    color: const Color(0xFF00897B),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AccountPage()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashboard Card ────────────────────────────────────────────────────────────
class _DashCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;
  final int badgeCount;

  const _DashCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sublabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Badge
            if (badgeCount > 0)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
