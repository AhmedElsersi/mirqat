/// `mm:ss.mmm`, the way the segment list shows a position in the recording.
String formatTimecode(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:'
    '${(d.inSeconds % 60).toString().padLeft(2, '0')}.'
    '${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}';

/// Reads a position an operator typed: `75.4` (seconds), `1:15.4`, or
/// `1:02:15.4`. Null for anything else — a typo must not become a cut.
Duration? parseTimecode(String input) {
  final String text = input.trim();
  if (text.isEmpty) return null;

  final List<String> parts = text.split(':');
  if (parts.length > 3) return null;

  double seconds = 0;
  for (int i = 0; i < parts.length; i++) {
    final bool last = i == parts.length - 1;
    // Only the seconds may carry a fraction, and nothing may be negative.
    final num? value = last
        ? double.tryParse(parts[i])
        : int.tryParse(parts[i]);
    if (value == null || value < 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    // Minutes and seconds under an hour or a minute mark stay under 60.
    if (parts.length > 1 && i > 0 && value >= 60) return null;
    seconds = seconds * 60 + value;
  }
  return Duration(milliseconds: (seconds * 1000).round());
}
