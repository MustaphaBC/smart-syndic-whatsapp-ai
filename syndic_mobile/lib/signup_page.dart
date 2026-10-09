import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main.dart';
import '../api_service.dart';
import '../app_theme.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage>
    with SingleTickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  // ── State flags ──────────────────────────────────────────────────────────────
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _codeVerified = false;
  bool _isVerifyingCode = false;
  bool _isLoading = false;
  String? _codeError;

  // ── Animation ────────────────────────────────────────────────────────────────
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    for (final c in [
      _nameCtrl,
      _emailCtrl,
      _passCtrl,
      _confirmCtrl,
      _codeCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Invite code verification ──────────────────────────────────────────────────
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _codeError = "Entrez un code d'invitation");
      return;
    }
    setState(() {
      _isVerifyingCode = true;
      _codeError = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$BASE_URL/api/verify-invite-code'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'code': code}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _codeVerified = true);
        showAppSnack(context, '✅ Code valide — vous pouvez continuer');
      } else {
        final body = json.decode(res.body);
        setState(() => _codeError = body['detail'] ?? 'Code invalide');
      }
    } catch (e) {
      setState(() => _codeError = 'Erreur réseau');
    } finally {
      if (mounted) setState(() => _isVerifyingCode = false);
    }
  }

  // ── Email signup ──────────────────────────────────────────────────────────────
  Future<void> _signUpEmail() async {
    if (!_validateForm()) return;
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      await cred.user?.updateDisplayName(_nameCtrl.text.trim());
      await cred.user?.sendEmailVerification();
      await _markCodeUsed(_emailCtrl.text.trim());
      if (!mounted) return;
      showAppSnack(
        context,
        '✅ Compte créé ! Vérifiez votre email pour l\'activer.',
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _handleFirebaseError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markCodeUsed(String email) async {
    try {
      // use-invite-code requires auth — called after Firebase user creation
      await ApiService.post('/api/use-invite-code', {
        'code': _codeCtrl.text.trim().toUpperCase(),
        'email': email,
      });
    } catch (e) {
      debugPrint('markCodeUsed error: $e');
    }
  }

  // ── Validation ────────────────────────────────────────────────────────────────
  bool _validateForm() {
    if (_nameCtrl.text.trim().isEmpty) {
      showAppSnack(context, 'Entrez votre nom complet', isError: true);
      return false;
    }
    if (!_codeVerified) {
      showAppSnack(
        context,
        "Vérifiez d'abord le code d'invitation",
        isError: true,
      );
      return false;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      showAppSnack(
        context,
        'Les mots de passe ne correspondent pas',
        isError: true,
      );
      return false;
    }
    if (_passCtrl.text.length < 6) {
      showAppSnack(
        context,
        'Mot de passe trop court (min 6 caractères)',
        isError: true,
      );
      return false;
    }
    return true;
  }

  void _handleFirebaseError(FirebaseAuthException e) {
    final msgs = {
      'email-already-in-use': 'Cet email est déjà utilisé',
      'invalid-email': 'Email invalide',
      'weak-password': 'Mot de passe trop faible',
      'operation-not-allowed': 'Méthode de connexion non activée',
    };
    showAppSnack(
      context,
      msgs[e.code] ?? e.message ?? "Erreur d'inscription",
      isError: true,
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: scheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Créer un compte',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──────────────────────────────────────────────────
                  Center(
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.admin_panel_settings_rounded,
                        size: 38,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Accès administrateur',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      'Réservé aux syndics autorisés',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Invite code ──────────────────────────────────────────────
                  _SectionLabel("CODE D'INVITATION", scheme),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _codeCtrl,
                          label: "Code d'accès",
                          icon: Icons.vpn_key_rounded,
                          textCapitalization: TextCapitalization.characters,
                          errorText: _codeError,
                          enabled: !_codeVerified,
                          suffixIcon: _codeVerified
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.validated,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _codeVerified
                                ? AppColors.validated
                                : scheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          onPressed: _codeVerified
                              ? null
                              : (_isVerifyingCode ? null : _verifyCode),
                          child: _isVerifyingCode
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _codeVerified ? '✓ OK' : 'Vérifier',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Informations ─────────────────────────────────────────────
                  _SectionLabel('VOS INFORMATIONS', scheme),
                  const SizedBox(height: 8),
                  AppTextField(
                    controller: _nameCtrl,
                    label: 'Nom complet',
                    icon: Icons.badge_rounded,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _emailCtrl,
                    label: 'Adresse email',
                    icon: Icons.email_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),

                  // ── Mot de passe ─────────────────────────────────────────────
                  _SectionLabel('MOT DE PASSE', scheme),
                  const SizedBox(height: 8),
                  AppTextField(
                    controller: _passCtrl,
                    label: 'Mot de passe',
                    icon: Icons.lock_rounded,
                    obscureText: _obscurePass,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _confirmCtrl,
                    label: 'Confirmer le mot de passe',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscureConfirm,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoBanner(
                    icon: Icons.mark_email_unread_rounded,
                    text:
                        'Un email de confirmation vous sera envoyé après l\'inscription.',
                    scheme: scheme,
                  ),
                  const SizedBox(height: 28),

                  // ── Submit ───────────────────────────────────────────────────
                  AppPrimaryButton(
                    label: 'Créer le compte',
                    icon: Icons.person_add_rounded,
                    isLoading: _isLoading,
                    onPressed: _codeVerified ? _signUpEmail : null,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton.icon(
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        size: 14,
                        color: scheme.primary,
                      ),
                      label: Text(
                        'Déjà un compte ? Se connecter',
                        style: TextStyle(color: scheme.primary),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Info Banner ───────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme scheme;
  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: scheme.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: scheme.primary.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final ColorScheme scheme;
  const _SectionLabel(this.text, this.scheme);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      color: scheme.primary,
    ),
  );
}
