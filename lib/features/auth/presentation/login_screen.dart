/// Email + password sign-in screen.
///
/// Submits to [AuthController.login]. The controller flips to
/// [AuthAuthenticated] on success, at which point the [GoRouter] redirect
/// bounces the user to `/home`. On failure, the [ApiException] is
/// rethrown and we surface it as a snackbar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/validators/input_validators.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_input.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome back',
                      style: textTheme.headlineMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Sign in to your SupaNotes account.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppInput(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      controller: _emailController,
                      prefixIcon: const Icon(Icons.email_outlined),
                      validator: (v) => EmailValidator.validate(v),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppInput(
                      labelText: 'Password',
                      obscureText: true,
                      enableObscureToggle: true,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      controller: _passwordController,
                      prefixIcon: const Icon(Icons.lock_outline),
                      validator: (v) => PasswordValidator.validate(v),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      text: 'Sign in',
                      isLoading: isLoading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      text: "Don't have an account? Create one",
                      variant: AppButtonVariant.secondary,
                      onPressed: isLoading
                          ? null
                          : () => context.go(AppRoutes.register),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
