import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard_page.dart';
import 'theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  static const routeName = '/login';

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSignUp = false;
  bool _signingIn = false;
  String? _loginError;
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _goToDashboard() {
    Navigator.of(context).pushReplacementNamed(DashboardPage.routeName);
  }

  Future<void> _submit() async {
    if (_signingIn) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final displayName = _displayNameController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _loginError = 'Please enter your email address.';
      });
      return;
    }

    if (password.length < 8) {
      setState(() {
        _loginError = 'Use a password with at least 8 characters.';
      });
      return;
    }
    if (_isSignUp && displayName.isEmpty) {
      setState(() => _loginError = 'Please enter your name.');
      return;
    }

    setState(() {
      _signingIn = true;
      _loginError = null;
      _successMessage = null;
    });

    try {
      final response = _isSignUp
          ? await Supabase.instance.client.auth.signUp(
              email: email,
              password: password,
              data: {'display_name': displayName},
            )
          : await Supabase.instance.client.auth.signInWithPassword(
              email: email,
              password: password,
            );

      if (response.user == null) {
        throw Exception(_isSignUp ? 'Sign up failed.' : 'Login failed.');
      }

      if (!mounted) return;
      if (response.session != null) {
        _goToDashboard();
      } else {
        setState(() {
          _successMessage =
              'Account created. Check your email to confirm it, then sign in.';
          _isSignUp = false;
        });
      }
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _loginError = error.message;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loginError = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _signingIn = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _loginError = 'Enter your email address first.');
      return;
    }
    setState(() {
      _loginError = null;
      _successMessage = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() => _successMessage = 'Password reset email sent.');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _loginError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;

            return Row(
              children: [
                if (wide) const Expanded(flex: 11, child: _LoginStoryPanel()),
                Expanded(
                  flex: wide ? 10 : 1,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 64 : 24,
                        vertical: 32,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: _LoginForm(
                          emailController: _emailController,
                          passwordController: _passwordController,
                          displayNameController: _displayNameController,
                          obscurePassword: _obscurePassword,
                          isSignUp: _isSignUp,

                          onTogglePassword: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },

                          onContinue: _submit,
                          onResetPassword: _resetPassword,
                          onToggleMode: () {
                            setState(() {
                              _isSignUp = !_isSignUp;
                              _loginError = null;
                              _successMessage = null;
                            });
                          },
                          signingIn: _signingIn,
                          loginError: _loginError,
                          successMessage: _successMessage,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.emailController,
    required this.passwordController,
    required this.displayNameController,
    required this.obscurePassword,
    required this.isSignUp,
    required this.onTogglePassword,
    required this.onContinue,
    required this.onResetPassword,
    required this.onToggleMode,
    required this.signingIn,
    required this.loginError,
    required this.successMessage,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController displayNameController;

  final bool obscurePassword;
  final bool isSignUp;
  final VoidCallback onTogglePassword;

  final Future<void> Function() onContinue;
  final Future<void> Function() onResetPassword;
  final VoidCallback onToggleMode;
  final bool signingIn;
  final String? loginError;
  final String? successMessage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(alignment: Alignment.centerLeft, child: _BrandMark()),

        const SizedBox(height: 46),

        Text(
          isSignUp ? 'Create your account' : 'Welcome back',
          style: textTheme.displaySmall,
        ),

        const SizedBox(height: 10),

        Text(
          isSignUp
              ? 'Start securely organizing your bank activity in Mongolian tugriks.'
              : 'Sign in to see your spending, balance, and recent bank activity in one calm place.',
          style: textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),

        const SizedBox(height: 32),

        if (isSignUp) ...[
          TextField(
            key: const Key('displayNameField'),
            controller: displayNameController,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
        ],

        TextField(
          key: const Key('emailField'),
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),

        const SizedBox(height: 14),

        TextField(
          key: const Key('passwordField'),
          controller: passwordController,
          obscureText: obscurePassword,
          textInputAction: TextInputAction.done,
          enableSuggestions: false,
          autocorrect: false,
          autofillHints: [
            isSignUp ? AutofillHints.newPassword : AutofillHints.password,
          ],
          onSubmitted: (_) {
            if (!signingIn) {
              onContinue();
            }
          },
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: obscurePassword ? 'Show password' : 'Hide password',
              onPressed: onTogglePassword,
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        if (!isSignUp)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: signingIn ? null : onResetPassword,
              child: const Text('Forgot password?'),
            ),
          ),

        const SizedBox(height: 8),

        FilledButton(
          onPressed: signingIn
              ? null
              : () {
                  onContinue();
                },
          child: signingIn
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isSignUp ? 'Create account' : 'Sign in'),
        ),

        if (loginError != null) ...[
          const SizedBox(height: 12),
          Text(
            loginError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.coral, fontSize: 12),
          ),
        ],

        if (successMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            successMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.primary, fontSize: 12),
          ),
        ],

        const SizedBox(height: 22),

        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: [
            Text(
              isSignUp ? 'Already have an account?' : 'New to Mailance?',
              style: const TextStyle(color: AppColors.muted),
            ),
            TextButton(
              key: const Key('toggleAuthModeButton'),
              onPressed: signingIn ? null : onToggleMode,
              child: Text(isSignUp ? 'Sign in' : 'Create account'),
            ),
          ],
        ),

        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_rounded, size: 15, color: AppColors.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Your imported transactions are isolated to your account.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/mailance_logo.png',
          width: 42,
          height: 42,
          filterQuality: FilterQuality.high,
        ),
        const SizedBox(width: 11),
        const Text(
          'Mailance',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _LoginStoryPanel extends StatelessWidget {
  const _LoginStoryPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -90,
              child: Container(
                width: 310,
                height: 310,
                decoration: const BoxDecoration(
                  color: Color(0xFF225A49),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -130,
              left: -120,
              child: Container(
                width: 330,
                height: 330,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(54),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFA5E5CB),
                    ),
                  ),

                  const SizedBox(height: 28),

                  const Text(
                    'Your money story,\nwithout the spreadsheet.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.7,
                    ),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    'Mailance securely turns bank alerts from your inbox into a clear, useful daily overview.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 17,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 42),

                  const _MiniBalanceCard(),

                  const Spacer(flex: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBalanceCard extends StatelessWidget {
  const _MiniBalanceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: const Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AVAILABLE BALANCE',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  '₮12,480,500',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          CircleAvatar(
            radius: 23,
            backgroundColor: AppColors.mint,
            child: Icon(Icons.trending_up_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
