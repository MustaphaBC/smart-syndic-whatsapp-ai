import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'api_service.dart';
import 'app_theme.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Map<String, dynamic> _stats = {};
  bool _isLoadingStats = true;
  bool _isSavingName = false;
  bool _isSendingReset = false;

  final _nameCtrl = TextEditingController();
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isPhoneUser = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = _user?.displayName ?? '';
    _isPhoneUser =
        _user?.providerData.any((p) => p.providerId == 'phone') ?? false;
    _fetchStats();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  // ── API ─────────────────────────────────────────────────────────────────────
  Future<void> _fetchStats() async {
    setState(() => _isLoadingStats = true);
    try {
      final data = await ApiService.getAdminStats();
      if (mounted) setState(() => _stats = data);
    } catch (e) {
      debugPrint('Stats error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  // ── Update display name ──────────────────────────────────────────────────────
  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showAppSnack(context, 'Le nom ne peut pas être vide', isError: true);
      return;
    }
    setState(() => _isSavingName = true);
    try {
      await _user?.updateDisplayName(name);
      if (mounted) showAppSnack(context, '✅ Nom mis à jour');
    } catch (e) {
      if (mounted) showAppSnack(context, 'Erreur: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingName = false);
    }
  }

  // ── Email: send reset link ────────────────────────────────────────────────────
  Future<void> _sendPasswordReset() async {
    final email = _user?.email;
    if (email == null) return;
    setState(() => _isSendingReset = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      showAppSnack(context, '📧 Lien de réinitialisation envoyé à $email');
    } catch (e) {
      if (mounted) showAppSnack(context, 'Erreur: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  // ── Email: change password inline ─────────────────────────────────────────────
  Future<void> _changePassword() async {
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      showAppSnack(
        context,
        'Les mots de passe ne correspondent pas',
        isError: true,
      );
      return;
    }
    if (_newPassCtrl.text.length < 6) {
      showAppSnack(
        context,
        'Mot de passe trop court (min 6 car.)',
        isError: true,
      );
      return;
    }
    setState(() => _isSendingReset = true);
    try {
      // Re-authenticate first
      final email = _user?.email;
      if (email == null) return;
      final cred = EmailAuthProvider.credential(
        email: email,
        password: _currentPassCtrl.text,
      );
      await _user?.reauthenticateWithCredential(cred);
      await _user?.updatePassword(_newPassCtrl.text);
      if (!mounted) return;
      _currentPassCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      showAppSnack(context, '✅ Mot de passe modifié avec succès');
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          e.code == 'wrong-password'
              ? 'Mot de passe actuel incorrect'
              : e.message ?? 'Erreur',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Se déconnecter',
        message: 'Voulez-vous vous déconnecter de votre compte ?',
        confirmLabel: 'Déconnecter',
        confirmColor: Colors.red,
      ),
    );
    if (confirmed == true) await FirebaseAuth.instance.signOut();
  }

  // ── DELETE ACCOUNT ────────────────────────────────────────────────────────────
  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Supprimer le compte',
        message:
            'Cette action est irréversible. Votre compte sera définitivement supprimé.',
        confirmLabel: 'Supprimer',
        confirmColor: Colors.red,
        isDestructive: true,
      ),
    );
    if (confirmed != true) return;
    try {
      await _user?.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login' && mounted) {
        showAppSnack(
          context,
          'Reconnectez-vous avant de supprimer votre compte',
          isError: true,
        );
      }
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = _user;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Mon Compte')),
      body: RefreshIndicator(
        onRefresh: _fetchStats,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            // ── Profile header ────────────────────────────────────────────
            _ProfileHeader(user: user, scheme: scheme),
            const SizedBox(height: 20),

            // ── Admin stats ───────────────────────────────────────────────
            const SectionHeader(label: 'Activité de modération'),
            const SizedBox(height: 12),
            _isLoadingStats
                ? AppCard(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: scheme.primary),
                      ),
                    ),
                  )
                : _StatsGrid(stats: _stats, scheme: scheme),
            const SizedBox(height: 24),

            // ── Informations personnelles ─────────────────────────────────
            const SectionHeader(label: 'Informations personnelles'),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                children: [
                  AppTextField(
                    controller: _nameCtrl,
                    label: 'Nom complet',
                    icon: Icons.badge_rounded,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 14),
                  // Email (read-only display)
                  if (user?.email != null)
                    _InfoRow(
                      icon: Icons.email_rounded,
                      label: 'Email',
                      value: user!.email!,
                      scheme: scheme,
                    ),
                  if (user?.phoneNumber != null)
                    _InfoRow(
                      icon: Icons.phone_rounded,
                      label: 'Téléphone',
                      value: user!.phoneNumber!,
                      scheme: scheme,
                    ),
                  const SizedBox(height: 16),
                  AppPrimaryButton(
                    label: 'Enregistrer le nom',
                    icon: Icons.save_rounded,
                    isLoading: _isSavingName,
                    onPressed: _saveName,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Sécurité ──────────────────────────────────────────────────
            const SectionHeader(label: 'Sécurité & Mot de passe'),
            const SizedBox(height: 12),
            if (_isPhoneUser)
              AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.phone_android_rounded,
                          color: scheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Compte lié à un numéro de téléphone.\nLa gestion du mot de passe n\'est pas applicable.',
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              AppCard(
                child: Column(
                  children: [
                    // Quick reset by email
                    _ActionTile(
                      icon: Icons.mail_rounded,
                      title: 'Réinitialisation par email',
                      subtitle: 'Recevoir un lien sur ${user?.email ?? ''}',
                      color: scheme.primary,
                      isLoading: _isSendingReset,
                      onTap: _sendPasswordReset,
                    ),
                    Divider(
                      height: 24,
                      color: scheme.outline.withValues(alpha: 0.1),
                    ),
                    // Or change inline
                    const Text(
                      'Ou changer directement',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _currentPassCtrl,
                      label: 'Mot de passe actuel',
                      icon: Icons.lock_rounded,
                      obscureText: _obscureCurrent,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureCurrent
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _newPassCtrl,
                      label: 'Nouveau mot de passe',
                      icon: Icons.lock_open_rounded,
                      obscureText: _obscureNew,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNew
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _confirmPassCtrl,
                      label: 'Confirmer le nouveau mot de passe',
                      icon: Icons.lock_outline_rounded,
                      obscureText: _obscureConfirm,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppPrimaryButton(
                      label: 'Changer le mot de passe',
                      icon: Icons.lock_reset_rounded,
                      isLoading: _isSendingReset,
                      onPressed: _changePassword,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // ── Session ───────────────────────────────────────────────────
            const SectionHeader(label: 'Session'),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                children: [
                  _ActionTile(
                    icon: Icons.exit_to_app_rounded,
                    title: 'Se déconnecter',
                    subtitle: 'Fermer la session sur cet appareil',
                    color: Colors.orange,
                    onTap: _signOut,
                  ),
                  Divider(height: 20, color: Colors.red.withValues(alpha: 0.1)),
                  _ActionTile(
                    icon: Icons.delete_forever_rounded,
                    title: 'Supprimer le compte',
                    subtitle:
                        'Action irréversible — toutes les données seront perdues',
                    color: Colors.red,
                    onTap: _deleteAccount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // App version
            Center(
              child: Text(
                'Syndic IA  •  v1.0.0',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile Header ────────────────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final User? user;
  final ColorScheme scheme;
  const _ProfileHeader({required this.user, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final name = user?.displayName ?? user?.email?.split('@').first ?? 'Admin';
    final initials = name.trim().isEmpty
        ? 'A'
        : name
              .trim()
              .split(' ')
              .map((w) => w.isNotEmpty ? w[0] : '')
              .take(2)
              .join()
              .toUpperCase();
    final isEmail =
        user?.providerData.any((p) => p.providerId == 'password') ?? false;
    final verified = user?.emailVerified ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? user?.phoneNumber ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Auth provider badge
                    _Badge(
                      icon: isEmail ? Icons.email_rounded : Icons.phone_rounded,
                      label: isEmail ? 'Email' : 'SMS',
                    ),
                    const SizedBox(width: 6),
                    // Verification status
                    if (isEmail)
                      _Badge(
                        icon: verified
                            ? Icons.verified_rounded
                            : Icons.warning_rounded,
                        label: verified ? 'Vérifié' : 'Non vérifié',
                        color: verified
                            ? AppColors.validated
                            : AppColors.pending,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge({
    required this.icon,
    required this.label,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// ── Stats Grid ────────────────────────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  final ColorScheme scheme;
  const _StatsGrid({required this.stats, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final validated = stats['tickets_validated'] ?? 0;
    final modified = stats['tickets_modified'] ?? 0;
    final p0Handled = stats['p0_handled'] ?? 0;
    final avgMinutes = stats['avg_validation_minutes'] ?? 0;
    // ignore: unused_local_variable
    final total = stats['total_actions'] ?? 0;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          value: '$validated',
          label: 'Tickets validés',
          icon: Icons.check_circle_rounded,
          color: AppColors.validated,
          scheme: scheme,
        ),
        _StatCard(
          value: '$modified',
          label: 'Réponses modifiées',
          icon: Icons.edit_rounded,
          color: scheme.primary,
          scheme: scheme,
        ),
        _StatCard(
          value: '$p0Handled',
          label: 'Urgences P0 traitées',
          icon: Icons.local_fire_department_rounded,
          color: AppColors.p0,
          scheme: scheme,
        ),
        _StatCard(
          value: avgMinutes > 0 ? '${avgMinutes}min' : '—',
          label: 'Temps moyen validation',
          icon: Icons.timer_rounded,
          color: AppColors.p3,
          scheme: scheme,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  final ColorScheme scheme;
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border(left: BorderSide(color: color, width: 4)),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );
}

// ── Info Row ──────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final ColorScheme scheme;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const Spacer(),
        Icon(
          Icons.lock_rounded,
          size: 14,
          color: scheme.onSurface.withValues(alpha: 0.2),
        ),
      ],
    ),
  );
}

// ── Action Tile ───────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: color.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

// ── Confirm Dialog ────────────────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title, message, confirmLabel;
  final Color confirmColor;
  final bool isDestructive;
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: confirmColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isDestructive
                  ? Icons.delete_forever_rounded
                  : Icons.exit_to_app_rounded,
              color: confirmColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.7),
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Annuler',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            confirmLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
