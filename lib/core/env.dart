/// Build-time configuration. Values are injected with --dart-define in CI.
/// The service-role key is deliberately absent: it only lives in Edge Functions.
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True only when both defines were supplied at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const String defaultCurrency = 'ETB';

  /// VAT is stored as a fraction (0.15 = 15%) in `app_settings.vat_rate`,
  /// matching the rest of the app. The Settings screen multiplies by 100 for
  /// display only.
  static const double defaultVatRate = 0.15;
}
