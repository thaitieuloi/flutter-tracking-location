import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized Supabase configuration.
/// All Supabase credentials are loaded from .env file.
class SupabaseConfig {
  static String get url => dotenv.env['SUPABASE_URL'] ?? '';
  static String get anonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  /// Validate that all required environment variables are set.
  static void validate() {
    if (url.isEmpty) {
      throw Exception('SUPABASE_URL is not set in .env file');
    }
    if (anonKey.isEmpty) {
      throw Exception('SUPABASE_ANON_KEY is not set in .env file');
    }
  }
}
