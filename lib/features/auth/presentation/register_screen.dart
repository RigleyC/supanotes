/// New-account sign-up screen.
///
/// Mirrors the [LoginScreen] layout but asks for a display name and
/// confirms the password. The minimum password length is 8 characters
/// to match the typical backend constraint.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/features/auth/presentation/widgets/auth_button.dart';
import 'package:supanotes/features/auth/presentation/widgets/auth_form_field.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            name: _nameController.text.trim(),
          );
      // Router will redirect to /home on the AuthAuthenticated state flip.
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

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
                      'Create your account',
                      style: textTheme.headlineMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Capture anything. The agent organises it for you.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AuthFormField(
                      label: 'Name',
                      hint: 'How should we greet you?',
                      keyboardType: TextInputType.name,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                      controller: _nameController,
                      prefixIcon: const Icon(Icons.person_outline),
                      validator: _validateName,
                    ),
                    AuthFormField(
                      label: 'Email',
                      hint: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.newUsername],
                      textInputAction: TextInputAction.next,
                      controller: _emailController,
                      prefixIcon: const Icon(Icons.email_outlined),
                      validator: _validateEmail,
                    ),
                    AuthFormField(
                      label: 'Password',
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      controller: _passwordController,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      validator: _validatePassword,
                    ),
                    AuthFormField(
                      label: 'Confirm password',
                      obscureText: _obscureConfirm,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      controller: _confirmController,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscureConfirm = !_obscureConfirm,
                        ),
                      ),
                      validator: (value) => _validateConfirm(
                        value,
                        expected: _passwordController.text,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AuthButton(
                      label: 'Create account',
                      isLoading: _isSubmitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => context.go('/login'),
                      child: const Text('Already have an account? Sign in'),
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

String? _validateName(String? value) {
  if (value == null || value.trim().isEmpty) return 'Name is required';
  return null;
}

String? _validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Email is required';
  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!emailRegex.hasMatch(v)) return 'Enter a valid email address';
  return null;
}

String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Password is required';
  if (value.length < 8) return 'Password must be at least 8 characters';
  return null;
}

String? _validateConfirm(String? value, {required String expected}) {
  if (value == null || value.isEmpty) return 'Please re-enter your password';
  if (value != expected) return 'Passwords do not match';
  return null;
}
