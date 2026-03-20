import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'config/supabase_config.dart';
import 'providers/app_provider.dart';
import 'services/supabase_service.dart';
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
        _updateStatus('online');
      } else if (data.event == AuthChangeEvent.signedOut) {
        _updateStatus('offline');
      }
    });

    // Initial check
    if (Supabase.instance.client.auth.currentSession != null) {
      _updateStatus('online');
    }
  }

  @override
  void dispose() {
    _updateStatus('idle');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String? _lastStatus;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log('📱 [App] Lifecycle state changed to: $state');
    switch (state) {
      case AppLifecycleState.resumed:
        _updateStatus('online');
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _updateStatus('idle');
        break;
      case AppLifecycleState.detached:
        // Even if detached, background service might still be alive
        _updateStatus('idle');
        break;
    }
  }

  void _updateStatus(String status) {
    if (_lastStatus == status) {
      log('⏭️ [App] Skipping redundant status update: $status');
      return;
    }
    
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      _lastStatus = status;
      log('🔄 [App] Requesting status update: $userId -> $status');
      // We use await to ensure chronological order if this was in an async block,
      // but here we just want to ensure we don't spam.
      _supabaseService.updateUserStatus(userId, status).then((_) {
        log('✅ [App] Status update completed: $status');
      }).catchError((e) {
        log('❌ [App] Status update failed: $status | $e');
        _lastStatus = null; // Clear on error to allow retry
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
