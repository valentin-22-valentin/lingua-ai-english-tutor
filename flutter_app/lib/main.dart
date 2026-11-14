import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'screens.dart';
import 'theme_compat.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'ui_text.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LinguaApp(controller: AppController()));
}

class LinguaApp extends StatefulWidget {
  final AppController controller;
  final bool initialize;
  const LinguaApp(
      {super.key, required this.controller, this.initialize = true});
  @override
  State<LinguaApp> createState() => _LinguaAppState();
}

class _LinguaAppState extends State<LinguaApp> {
  @override
  void initState() {
    super.initState();
    if (widget.initialize) {
      widget.controller.initialize();
    }
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => MaterialApp(
            title: 'Lingua',
            locale: Locale(widget.controller.appLanguage),
            supportedLocales: [for (final code in UiText.codes) Locale(code)],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            debugShowCheckedModeBanner: false,
            theme: linguaTheme(Brightness.light),
            darkTheme: linguaTheme(Brightness.dark),
            themeMode: widget.controller.theme,
            themeAnimationDuration:
                MediaQueryData.fromView(View.of(context)).disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
            home: AppShell(controller: widget.controller),
          ));
}

ThemeData linguaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xff087e79), brightness: brightness)
      .copyWith(
    primary: dark ? const Color(0xff75d9c9) : const Color(0xff096c65),
    onPrimary: dark ? const Color(0xff082923) : Colors.white,
    surface: dark ? const Color(0xff121e1e) : const Color(0xfffaf9f5),
    onSurface: dark ? const Color(0xffeef4ed) : const Color(0xff19332f),
    onSurfaceVariant: dark ? const Color(0xffa3bbb2) : const Color(0xff526761),
    background: dark ? const Color(0xff1a2927) : const Color(0xfff0f0e9),
    surfaceVariant: dark ? const Color(0xff293c36) : const Color(0xffe4e9df),
    outlineVariant: dark ? const Color(0xff34433d) : const Color(0xffd9e0d5),
    secondary: dark ? const Color(0xffffad8e) : const Color(0xffa74529),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Segoe UI',
    textTheme: TextTheme(
      displaySmall: TextStyle(
          fontSize: 42,
          letterSpacing: -1.8,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface),
      headlineMedium: TextStyle(
          fontSize: 30,
          letterSpacing: -1.1,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface),
      titleLarge: TextStyle(
          fontSize: 21,
          letterSpacing: -.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface),
      titleMedium: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
      bodyLarge: TextStyle(fontSize: 16, height: 1.6, color: scheme.onSurface),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: scheme.onSurface),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)))),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant)),
  );
}
