import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'config/supabase_config.dart';
import 'providers/app_provider.dart';
import 'services/supabase_service.dart';
import 'services/native_lifecycle_service.dart';
import 'services/background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Validate config
  SupabaseConfig.validate();

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  
  // Initialize Background Location Service
  await BackgroundServiceManager.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider()..initialize(),
      child: MaterialApp(
        title: 'Family Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.system,
        home: const AuthWrapper(),
      ),
    );
  }
}

/// Wrapper widget that listens to Supabase auth state changes
/// and navigates between login and map screens accordingly.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  late final Stream<AuthState> _authStream;
  final _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStream = Supabase.instance.client.auth.onAuthStateChange;
    
    // Listen to Auth state changes to set status
    _authStream.listen((data) {
      if (data.event == AuthChangeEvent.signedIn || data.session != null) {
        _updateStatus('online', setToken: true);
        _syncNativeCredentials(data.session);
      } else if (data.event == AuthChangeEvent.signedOut) {
        _updateStatus('offline');
        NativeLifecycleService.clearCredentials();
      }
    });

    // Initial check
    final currentSession = Supabase.instance.client.auth.currentSession;
    if (currentSession != null) {
      _updateStatus('online', setToken: true);
      _syncNativeCredentials(currentSession);
    }
  }

  /// Pass credentials to native Android layer so ProcessLifecycleOwner
  /// can send status updates even when the Dart VM is killed.
  /// Also persist refresh_token for background service session recovery.
  void _syncNativeCredentials(Session? session) async {
    if (session == null) return;
    final userId = session.user.id;
    final accessToken = session.accessToken;
    
    NativeLifecycleService.saveCredentials(
      supabaseUrl: SupabaseConfig.url,
      supabaseKey: SupabaseConfig.anonKey,
      userId: userId,
      accessToken: accessToken,
    );
    
    // Critical: save refresh_token so background service can recover auth
    // when access_token expires (~1h). Without this, background tracking
    // silently stops writing to DB after the token expires.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
    if (session.refreshToken != null) {
      await prefs.setString('refresh_token', session.refreshToken!);
    }
    // Save full session JSON so background isolate can call recoverSession() correctly.
    // recoverSession() expects the full JSON object, NOT just the raw token string.
    await prefs.setString('session_json', jsonEncode(session.toJson()));

    log('📱 [App] Native lifecycle credentials + tokens synced for: $userId');
  }

  @override
  void dispose() {
    _updateStatus('offline');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String? _lastStatus;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log('📱 [App] Lifecycle state changed to: $state');
    
    // Update a reliable flag for BackgroundService to read
    _updateForegroundFlag(state == AppLifecycleState.resumed);

    switch (state) {
      case AppLifecycleState.resumed:
        _updateStatus('online'); // Foreground - Xanh lá
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          _syncNativeCredentials(session);
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _updateStatus('idle'); // Background but not killed - Cam
        break;
      case AppLifecycleState.detached:
        _updateStatus('offline'); // App closed/killed - Tím (DB constraint: only online/idle/offline/logged_out)
        try {
          Provider.of<AppProvider>(context, listen: false).stopForegroundTrackingOnly();
        } catch (_) {}
        break;
    }
  }

  Future<void> _updateForegroundFlag(bool isForeground) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_app_foreground', isForeground);
    log('📱 [App] is_app_foreground flag set to: $isForeground');
  }

  void _updateStatus(String status, {bool setToken = false}) {
    if (_lastStatus == status && !setToken) {
      log('⏭️ [App] Skipping redundant status update: $status');
      return;
    }
    
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      _lastStatus = status;
      log('🔄 [App] Requesting status update: $userId -> $status (setToken: $setToken)');
      
      final Map<String, dynamic> data = {
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (setToken) {
        data['push_token'] = 'active_session_flutter';
      }

      Supabase.instance.client.from('profiles').update(data).eq('user_id', userId).then((_) {
        log('✅ [App] Status update completed: $status');
      }).catchError((e) {
        log('❌ [App] Status update failed: $status | $e');
        _lastStatus = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStream,
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Check for active session
        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const MapScreen();
        }

        return const LoginScreen();
      },
    );
  }
}

