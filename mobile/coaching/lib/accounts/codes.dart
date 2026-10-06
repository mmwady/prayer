String normalizeAccountCode(String input) {
  final value = input.trim();
  if (value.startsWith('iqtadi-')) return value;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority) return value;
  try {
    final fragment = Uri.splitQueryString(uri.fragment);
    final pairing = fragment['pair']?.trim();
    if (pairing != null && pairing.isNotEmpty) return 'iqtadi-pair:$pairing';
  } on FormatException {
    return value;
  }
  return value;
}

String detectAccountCodeKind(String input, {String fallback = 'MOSQUE'}) {
  final value = normalizeAccountCode(input);
  if (value.startsWith('iqtadi-pair:')) return 'DEVICE';
  if (value.startsWith('iqtadi-family:')) return 'FAMILY';
  if (value.startsWith('iqtadi-group:')) return 'MOSQUE';
  if (value.startsWith('iqtadi-attend:')) return 'ATTENDANCE';
  return fallback;
}
