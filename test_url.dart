import 'dart:async';

void main() {
  // Test URL detection patterns
  final urlPatterns = [
    // Full URL with protocol
    RegExp(r'^https?://[\w\-]+(\.[\w\-]+)+([\w\-\.,@?^=%&:/~\+#]*[\w\-\@?^=%&/~\+#])?$', caseSensitive: false),
    // URL without protocol
    RegExp(r'^www\.[\w\-]+(\.[\w\-]+)+([\w\-\.,@?^=%&:/~\+#]*[\w\-\@?^=%&/~\+#])?$', caseSensitive: false),
    // Simple domain patterns
    RegExp(r'^[\w\-]+(\.[\w\-]+)*\.(com|org|net|edu|gov|io|co|uk|de|fr|jp|cn|au|ca|in|br|mx|ru|it|es|nl|pl|se|no|dk|fi|be|ch|at|cz|hu|gr|pt|ie|sk|si|hr|bg|ro|lt|lv|ee|lu|mt|cy)([\w\-\.,@?^=%&:/~\+#]*[\w\-\@?^=%&/~\+#])?$', caseSensitive: false),
  ];
  
  // Test URLs
  final testUrls = [
    'https://www.google.com',
    'http://example.com',
    'www.github.com',
    'flutter.dev',
    'stackoverflow.com/questions/123',
    'google.com',
    'example.org',
    'test.edu',
    'site.gov',
    'invalid-url',
    'not.a.real.domain.xyz',
    'just-text'
  ];
  
  bool isUrl(String text) {
    text = text.trim();
    return urlPatterns.any((pattern) => pattern.hasMatch(text));
  }
  
  print('URL Detection Test Results:');
  print('=' * 40);
  
  for (String url in testUrls) {
    bool detected = isUrl(url);
    print('${url.padRight(30)} -> ${detected ? "✓ URL" : "✗ Not URL"}');
  }
  
  print('\nPattern Breakdown:');
  print('=' * 40);
  
  for (String url in testUrls.where((u) => isUrl(u))) {
    print('\n"$url" matches:');
    for (int i = 0; i < urlPatterns.length; i++) {
      if (urlPatterns[i].hasMatch(url.trim())) {
        String patternName = ['Full URL with protocol', 'URL without protocol', 'Simple domain patterns'][i];
        print('  - $patternName');
      }
    }
  }
}
