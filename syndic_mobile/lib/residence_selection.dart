// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_theme.dart';
import 'dashboard_grid.dart';
import 'residents_page.dart';

class ResidenceSelectionPage extends StatefulWidget {
  final String targetRoute;
  const ResidenceSelectionPage({super.key, this.targetRoute = 'dashboard'});
  @override
  State<ResidenceSelectionPage> createState() => _ResidenceSelectionPageState();
}

class _ResidenceSelectionPageState extends State<ResidenceSelectionPage> {
  List<dynamic> residences = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchResidences();
  }

  Future<void> _fetchResidences() async {
    try {
      final data = await ApiService.getResidences();
      if (mounted) {
        setState(() {
          residences = data;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erreur résidences: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Add residence bottom sheet ───────────────────────────────────────────────
  void _showAddResidenceSheet() {
    final nameCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final unitsCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final scheme = Theme.of(ctx).colorScheme;

          Future<void> save() async {
            if (!formKey.currentState!.validate()) return;
            setSheetState(() => isSaving = true);
            try {
              await ApiService.post('/api/residences', {
                'name': nameCtrl.text.trim(),
                'city': cityCtrl.text.trim(),
                'address': addressCtrl.text.trim(),
                'units_count': int.tryParse(unitsCtrl.text.trim()) ?? 0,
              });
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _fetchResidences();
              showAppSnack(
                context,
                '✅ Résidence "${nameCtrl.text.trim()}" créée',
              );
            } catch (e) {
              if (ctx.mounted) {
                showAppSnack(context, '❌ Erreur: $e', isError: true);
              }
            } finally {
              if (ctx.mounted) setSheetState(() => isSaving = false);
            }
          }

          return Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: scheme.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.add_business_rounded,
                          color: scheme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Nouvelle résidence',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Nom (obligatoire)
                  _FormField(
                    controller: nameCtrl,
                    label: 'Nom de la résidence *',
                    hint: 'Ex: Résidence Atlas, Immeuble Marina...',
                    icon: Icons.apartment_rounded,
                    scheme: scheme,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Le nom est obligatoire'
                        : null,
                  ),
                  const SizedBox(height: 12),

                  // Ville
                  _FormField(
                    controller: cityCtrl,
                    label: 'Ville',
                    hint: 'Ex: Fès, Casablanca, Rabat...',
                    icon: Icons.location_city_rounded,
                    scheme: scheme,
                  ),
                  const SizedBox(height: 12),

                  // Adresse
                  _FormField(
                    controller: addressCtrl,
                    label: 'Adresse',
                    hint: 'Ex: Rue Ibn Battouta, Quartier Agdal...',
                    icon: Icons.place_rounded,
                    scheme: scheme,
                  ),
                  const SizedBox(height: 12),

                  // Nombre d'unités
                  _FormField(
                    controller: unitsCtrl,
                    label: 'Nombre d\'appartements',
                    hint: 'Ex: 24',
                    icon: Icons.door_front_door_rounded,
                    scheme: scheme,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      if (int.tryParse(v.trim()) == null) {
                        return 'Nombre invalide';
                      }
                      if (int.parse(v.trim()) < 0) return 'Doit être positif';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Bouton créer
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        shadowColor: scheme.primary.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: isSaving ? null : save,
                      icon: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: Text(
                        isSaving ? 'Création...' : 'Créer la résidence',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSupervision = widget.targetRoute == 'dashboard';

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(isSupervision ? 'Supervision' : 'Gérer Résidents'),
        centerTitle: true,
        actions: [
          // Bouton ajouter résidence (toujours visible)
          IconButton(
            icon: const Icon(Icons.add_business_rounded),
            tooltip: 'Nouvelle résidence',
            onPressed: _showAddResidenceSheet,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : residences.isEmpty
          ? _buildEmpty(scheme)
          : RefreshIndicator(
              onRefresh: _fetchResidences,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio:
                        0.95, // légèrement plus haut pour afficher ville
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: residences.length,
                  itemBuilder: (context, i) {
                    final res = residences[i];
                    return _ResidenceCard(
                      name: res['name'],
                      id: res['id'],
                      city: res['city'] ?? '',
                      unitsCount: res['units_count'] ?? 0,
                      isSupervision: isSupervision,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => isSupervision
                              ? DashboardGridPage(
                                  residenceId: res['id'],
                                  residenceName: res['name'],
                                )
                              : ResidentsPage(
                                  residenceId: res['id'],
                                  residenceName: res['name'],
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  Widget _buildEmpty(ColorScheme scheme) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.location_city_rounded,
          size: 64,
          color: scheme.onSurface.withValues(alpha: 0.2),
        ),
        const SizedBox(height: 16),
        Text(
          'Aucune résidence',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Appuyez sur + pour en créer une',
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _showAddResidenceSheet,
          icon: const Icon(Icons.add_business_rounded, size: 18),
          label: const Text('Créer une résidence'),
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Residence Card ────────────────────────────────────────────────────────────
class _ResidenceCard extends StatelessWidget {
  final String name, id, city;
  final int unitsCount;
  final bool isSupervision;
  final VoidCallback onTap;

  const _ResidenceCard({
    required this.name,
    required this.id,
    required this.city,
    required this.unitsCount,
    required this.isSupervision,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isSupervision ? scheme.primary : const Color(0xFF0288D1);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icône
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isSupervision
                      ? Icons.apartment_rounded
                      : Icons.people_rounded,
                  size: 26,
                  color: color,
                ),
              ),
              const SizedBox(height: 10),

              // Nom
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: scheme.onSurface,
                ),
              ),

              // Ville (si disponible)
              if (city.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 10,
                      color: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        city,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // Nb unités (si renseigné)
              if (unitsCount > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$unitsCount appts',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Form field helper ─────────────────────────────────────────────────────────
class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final ColorScheme scheme;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.scheme,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: scheme.primary, size: 20),
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
    ),
  );
}
