import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'screens.dart';
import 'ui_text.dart';

class AuthScreen extends StatefulWidget {
  final AppController controller;
  const AuthScreen({super.key, required this.controller});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false, obscure = true, validationAttempted = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    validationAttempted = true;
    if (!form.currentState!.validate()) {
      return;
    }
    await widget.controller.authenticate(email.text, password.text,
        username: register ? name.text : null);
    if (mounted) {
      password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, cs = Theme.of(context).colorScheme;
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Form(
                            key: form,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Brand(),
                                  const SizedBox(height: 20),
                                  DropdownButtonFormField<String>(
                                    value: c.appLanguage,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                        labelText: c.tr('interface')),
                                    items: [
                                      for (final code in UiText.codes)
                                        DropdownMenuItem(
                                            value: code,
                                            child: Text(UiText.names[code]!))
                                    ],
                                    onChanged: c.authenticating
                                        ? null
                                        : (value) async {
                                            await c
                                                .setInterfaceLanguage(value!);
                                            if (mounted &&
                                                validationAttempted) {
                                              form.currentState?.validate();
                                            }
                                          },
                                  ),
                                  const SizedBox(height: 54),
                                  Text(
                                      register
                                          ? c.tr('newAccount')
                                          : c.tr('welcome'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .displaySmall),
                                  const SizedBox(height: 14),
                                  Text(c.tr('authHelp'),
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant)),
                                  const SizedBox(height: 33),
                                  if (register) ...[
                                    TextFormField(
                                        controller: name,
                                        enabled: !c.authenticating,
                                        decoration: InputDecoration(
                                            labelText: c.tr('name')),
                                        textInputAction: TextInputAction.next,
                                        validator: (value) =>
                                            (value?.trim().length ?? 0) < 2
                                                ? c.tr('authNameShort')
                                                : null),
                                    const SizedBox(height: 14)
                                  ],
                                  TextFormField(
                                      controller: email,
                                      enabled: !c.authenticating,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.email
                                      ],
                                      textInputAction: TextInputAction.next,
                                      decoration: InputDecoration(
                                          labelText: c.tr('email')),
                                      validator: (value) =>
                                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                                  .hasMatch(value?.trim() ?? '')
                                              ? null
                                              : c.tr('authEmailInvalid')),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                      controller: password,
                                      enabled: !c.authenticating,
                                      obscureText: obscure,
                                      autofillHints: [
                                        register
                                            ? AutofillHints.newPassword
                                            : AutofillHints.password
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) => submit(),
                                      decoration: InputDecoration(
                                          labelText: c.tr('password'),
                                          suffixIcon: IconButton(
                                              tooltip: obscure
                                                  ? c.tr('showPassword')
                                                  : c.tr('hidePassword'),
                                              onPressed: () => setState(
                                                  () => obscure = !obscure),
                                              icon: Icon(obscure
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                      .visibility_off_outlined))),
                                      validator: (value) =>
                                          (value?.length ?? 0) <
                                                  (register ? 8 : 1)
                                              ? register
                                                  ? c.tr('authPasswordShort')
                                                  : c.tr('authPasswordRequired')
                                              : null),
                                  if (c.authError != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Text(c.authError!,
                                            style: TextStyle(color: cs.error))),
                                  if (c.authNotice != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Text(c.authNotice!,
                                            style:
                                                TextStyle(color: cs.primary))),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                          onPressed:
                                              c.authenticating ? null : submit,
                                          child: c.authenticating
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2))
                                              : Text(register
                                                  ? c.tr('register')
                                                  : c.tr('login')))),
                                  const SizedBox(height: 16),
                                  Center(
                                      child: TextButton(
                                          onPressed: c.authenticating
                                              ? null
                                              : () => setState(() {
                                                    register = !register;
                                                    c.authError = null;
                                                    c.authNotice = null;
                                                  }),
                                          child: Text(register
                                              ? c.tr('authHaveAccount')
                                              : c.tr('authNeedAccount')))),
                                  const SizedBox(height: 28),
                                  Text(c.tr('authSessionNote'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 11,
                                          height: 1.6,
                                          color: cs.onSurfaceVariant)),
                                  const SizedBox(height: 30),
                                  Center(
                                      child: IconButton(
                                          tooltip: c.tr('toggleTheme'),
                                          onPressed: () => c.setTheme(
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? ThemeMode.light
                                                  : ThemeMode.dark),
                                          icon: const Icon(
                                              Icons.brightness_6_outlined))),
                                ])))))));
  }
}
