import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://sfgjpefqqqjgpwjvarru.supabase.co';

  static const String supabaseAnonKey =
      'sb_publishable_y68Sg8CKhP-jGi1lrLiNFw_LsOfP7sI';

  static SupabaseClient get client => Supabase.instance.client;
}
