import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════════════════════
// APP THEME — Design tokens partagés dans toute l'application
// ══════════════════════════════════════════════════════════════════════════════

class AppColors {
  // Brand
  static const primary = Color(0xFF3D5AFE);
  static const secondary = Color(0xFF00B0FF);

  // Urgency
  static const p0 = Color(0xFFE53935); // Rouge critique
  static const p1 = Color(0xFFFB8C00); // Orange urgent
  static const p2 = Color(0xFF43A047); // Vert modéré
  static const p3 = Color(0xFF1E88E5); // Bleu faible

  // Status
  static const validated = Color(0xFF00C853);
  static const pending = Color(0xFFFF6D00);

  // Categories
  static const plomberie = Color(0xFF1E88E5);
  static const electricite = Color(0xFFFB8C00);
  static const securite = Color(0xFFE53935);
  static const administratif = Color(0xFF8E24AA);
  static const ascenseur = Color(0xFF00ACC1);
  static const nuisances = Color(0xFFE91E63);
  static const autre = Color(0xFF43A047);

  static Color urgencyColor(String? level) {
    switch (level) {
      case 'P0':
        return p0;
      case 'P1':
        return p1;
      case 'P2':
        return p2;
      case 'P3':
        return p3;
      default:
        return Colors.grey;
    }
  }

  static Color categoryColor(String? category) {
    switch (category) {
      case 'Plomberie':
        return plomberie;
      case 'Electricité':
        return electricite;
      case 'Sécurité':
      case 'SÉCURITÉ':
      case 'INCENDIE':
      case 'FUITE_GAZ':
        return securite;
      case 'Administratif':
        return administratif;
      case 'Ascenseur':
      case 'ASCENSEUR_URGENCE':
        return ascenseur;
      case 'Nuisances':
        return nuisances;
      default:
        return autre;
    }
  }

  static IconData categoryIcon(String? category) {
    switch (category) {
      case 'Plomberie':
        return Icons.water_drop_rounded;
      case 'Electricité':
        return Icons.bolt_rounded;
      case 'INCENDIE':
        return Icons.local_fire_department_rounded;
      case 'FUITE_GAZ':
        return Icons.gas_meter_rounded;
      case 'ASCENSEUR_URGENCE':
      case 'Ascenseur':
        return Icons.elevator_rounded;
      case 'INONDATION_MAJEURE':
        return Icons.flood_rounded;
      case 'SÉCURITÉ':
      case 'Sécurité':
        return Icons.shield_rounded;
      case 'Administratif':
        return Icons.description_rounded;
      case 'Nuisances':
        return Icons.volume_up_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }
}

class AppTheme {
  // Seeds
  static const _seed = Color(0xFF3D5AFE);

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: _seed,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    scaffoldBackgroundColor: const Color(0xFFF4F6FB),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Color(0xFF151528),
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    scaffoldBackgroundColor: const Color(0xFF12121F),
  );
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

/// Section header with accent bar
class SectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const SectionHeader({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Consistent card container
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? borderColor;
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? scheme.outline.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Styled text field
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? errorText;
  final bool enabled;
  final TextCapitalization textCapitalization;
  final String? hint;
  final int maxLines;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.errorText,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
    this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: enabled,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: scheme.primary, size: 20),
        suffixIcon: suffixIcon,
        errorText: errorText,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
    );
  }
}

/// Primary action button
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? color;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ?? scheme.primary;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          elevation: 3,
          shadowColor: bg.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Urgency badge chip
class UrgencyBadge extends StatelessWidget {
  final String level;
  const UrgencyBadge({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.urgencyColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        level,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Status badge
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isResolved = status == 'validated';
    final color = isResolved ? AppColors.validated : AppColors.pending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isResolved
                ? Icons.check_circle_rounded
                : Icons.hourglass_top_rounded,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isResolved ? 'Résolu' : 'En attente',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

void showAppSnack(
  BuildContext context,
  String msg, {
  Color? color,
  bool isError = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: color ?? (isError ? Colors.red : AppColors.validated),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ),
  );
}
