import 'package:flutter/material.dart' show Colors;

// The locked system_theme package has no OH implementation. Keep the existing
// blue fallback without a platform call; ThemeMode.system handles brightness.
const kOhosSystemAccentColor = Colors.blue;
