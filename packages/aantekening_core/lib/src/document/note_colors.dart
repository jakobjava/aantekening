/// Colours that mean more than a colour.
library;

/// Colours text and ink can have that are not one colour.
abstract final class NoteColors {
  /// No colour of its own: what lies beneath, inverted — black on the
  /// white paper, white over a dark picture, and between the two over
  /// anything else, so it can always be read.
  ///
  /// Kept as transparent white, which a build that does not know it draws
  /// as nothing, rather than as a colour it never was.
  static const int inverse = 0x00FFFFFF;
}
