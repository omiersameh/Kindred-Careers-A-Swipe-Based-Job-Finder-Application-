void main() {
  String input = 'AI & ML Engineer';
  print('Input: ' + input);
  print('Sanitized: ' + _sanitize(input));
}

String _sanitize(String input) {
  return input
      .replaceAll('/', ' & ')
      .replaceAll('\\', ' & ')
      .replaceAll(' _ ', ' & ')
      .replaceAll(RegExp(r'\s+&\s+'), ' & ')
      .trim();
}
