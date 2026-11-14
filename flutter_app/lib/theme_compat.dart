import 'package:flutter/material.dart';

// Material 3 surfaces expressed using Flutter 3.19's ColorScheme fields.
extension LinguaSurfaces on ColorScheme {
  Color get surfaceContainerLow => background;
  Color get surfaceContainerHighest => surfaceVariant;
}
