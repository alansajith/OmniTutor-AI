/// Configuration for multilingual support in OmniTutor.
class LanguageConfig {
  static const Map<String, String> languages = {
    'English': 'en-US',
    'Spanish': 'es-ES',
    'Hindi': 'hi-IN',
    'French': 'fr-FR',
    'Swahili': 'sw-KE',
  };

  static String getLocale(String language) {
    return languages[language] ?? 'en-US';
  }

  static List<String> get names => languages.keys.toList();
}
