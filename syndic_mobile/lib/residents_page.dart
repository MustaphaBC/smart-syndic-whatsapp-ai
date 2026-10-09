import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_theme.dart';

class ResidentsPage extends StatefulWidget {
  final String residenceId;
  final String residenceName;

  const ResidentsPage({
    super.key,
    required this.residenceId,
    required this.residenceName,
  });

  @override
  State<ResidentsPage> createState() => _ResidentsPageState();
}

class _ResidentsPageState extends State<ResidentsPage> {
  List<dynamic> residents = [];
  bool isLoading = false;
  bool isSending = false;
  String _search = '';

  List<dynamic> get _filtered => _search.isEmpty
      ? residents
      : residents.where((r) {
          final name = (r['name'] ?? '').toString().toLowerCase();
          final unit = (r['unit'] ?? '').toString().toLowerCase();
          final phone = (r['phone'] ?? '').toString().toLowerCase();
          return name.contains(_search) ||
              unit.contains(_search) ||
              phone.contains(_search);
        }).toList();

  @override
  void initState() {
    super.initState();
    _fetchResidents();
  }

  // Auth centralisé dans ApiService

  // ── API ─────────────────────────────────────────────────────────────────────
  Future<void> _fetchResidents() async {
    setState(() => isLoading = true);
    try {
      final data = await ApiService.getResidents(widget.residenceId);
      if (mounted) setState(() => residents = data);
    } catch (e) {
      debugPrint('Erreur résidents: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _saveResident(String unit, String name, String phone) async {
    try {
      await ApiService.post('/api/residents', {
        'unit': unit,
        'name': name,
        'phone': phone,
        'residence_id': widget.residenceId,
      });
      if (!mounted) return;
      Navigator.pop(context);
      _fetchResidents();
      showAppSnack(context, '✅ $name ajouté (Appt $unit)');
    } catch (e) {
      if (mounted) showAppSnack(context, '❌ Erreur: $e', isError: true);
    }
  }

  Future<void> _updateResident({
    required String oldUnit,
    required String newUnit,
    required String newName,
    required String newPhone,
  }) async {
    try {
      await ApiService.put('/api/residents/$oldUnit', {
        'old_unit': oldUnit,
        'new_unit': newUnit,
        'new_name': newName,
        'new_phone': newPhone,
        'residence_id': widget.residenceId,
      });
      if (!mounted) return;
      Navigator.pop(context);
      _fetchResidents();
      showAppSnack(context, '✅ Résident modifié');
    } catch (e) {
      if (mounted) showAppSnack(context, '❌ Erreur: $e', isError: true);
    }
  }

  Future<void> _deleteResident(String unit) async {
    try {
      await ApiService.delete(
        '/api/residents/$unit?residence_id=${widget.residenceId}',
      );
      if (mounted) {
        _fetchResidents();
        showAppSnack(context, '🗑️ Résident supprimé');
      }
    } catch (e) {
      debugPrint('Erreur delete: $e');
    }
  }

  Future<void> _sendBroadcast(String message) async {
    setState(() => isSending = true);
    Navigator.pop(context);
    try {
      await ApiService.post('/api/broadcast', {
        'message': message,
        'residence_id': widget.residenceId,
      });
      if (mounted) showAppSnack(context, '📢 Annonce envoyée !');
    } catch (e) {
      if (mounted) showAppSnack(context, 'Erreur: $e', isError: true);
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  Future<void> _addRule(String rule) async {
    setState(() => isSending = true);
    Navigator.pop(context);
    try {
      await ApiService.post('/api/add-rule', {'rule': rule});
      if (mounted) {
        showAppSnack(
          context,
          '🧠 Règle mémorisée par l\'IA !',
          color: const Color(0xFF7C4DFF),
        );
      }
    } catch (e) {
      debugPrint('Erreur add-rule: $e');
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────
  void _showEditDialog({Map? resident}) {
    final isEditing = resident != null;
    final oldUnit = resident?['unit']?.toString() ?? '';
    final unitC = TextEditingController(text: resident?['unit']?.toString());
    final nameC = TextEditingController(text: resident?['name']?.toString());
    final phoneC = TextEditingController(
      text: resident?['phone']?.toString().replaceAll('whatsapp:', ''),
    );
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (isEditing ? Colors.orange : scheme.primary)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isEditing ? Icons.edit_rounded : Icons.person_add_rounded,
                    color: isEditing ? Colors.orange : scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isEditing ? 'Modifier le résident' : 'Nouveau résident',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: unitC,
              label: 'Appartement',
              icon: Icons.home_rounded,
              enabled: !isEditing,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: nameC,
              label: 'Nom complet',
              icon: Icons.person_rounded,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: phoneC,
              label: 'Téléphone',
              icon: Icons.phone_rounded,
              hint: '+212XXXXXXXXX',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            AppPrimaryButton(
              label: isEditing
                  ? 'Enregistrer les modifications'
                  : 'Ajouter le résident',
              icon: isEditing ? Icons.save_rounded : Icons.person_add_rounded,
              color: isEditing ? Colors.orange : null,
              onPressed: () {
                if (isEditing) {
                  _updateResident(
                    oldUnit: oldUnit,
                    newUnit: unitC.text.trim(),
                    newName: nameC.text.trim(),
                    newPhone: phoneC.text.trim(),
                  );
                } else {
                  _saveResident(
                    unitC.text.trim(),
                    nameC.text.trim(),
                    phoneC.text.trim(),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(String unit, String name) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.delete_rounded,
                color: Colors.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Supprimer',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'Supprimer $name (Appt $unit) ?\nCette action est irréversible.',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text('Supprimer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _deleteResident(unit);
            },
          ),
        ],
      ),
    );
  }

  void _showBroadcastDialog() {
    final c = TextEditingController();
    // ignore: unused_local_variable
    final scheme = Theme.of(context).colorScheme;
    _showTextInputDialog(
      title: 'Annonce globale',
      icon: Icons.campaign_rounded,
      iconColor: const Color(0xFF0288D1),
      hint: 'Message pour tous les résidents...',
      controller: c,
      buttonLabel: 'Envoyer à tous',
      buttonColor: const Color(0xFF0288D1),
      onConfirm: () => _sendBroadcast(c.text),
    );
  }

  void _showRuleDialog() {
    final c = TextEditingController();
    _showTextInputDialog(
      title: 'Enseigner une règle',
      icon: Icons.psychology_rounded,
      iconColor: const Color(0xFF7C4DFF),
      hint: 'Ex: Le code wifi est 1234',
      controller: c,
      buttonLabel: 'Mémoriser',
      buttonColor: const Color(0xFF7C4DFF),
      onConfirm: () => _addRule(c.text),
    );
  }

  void _showTextInputDialog({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String hint,
    required TextEditingController controller,
    required String buttonLabel,
    required Color buttonColor,
    required VoidCallback onConfirm,
  }) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: controller,
              label: title,
              icon: icon,
              hint: hint,
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: buttonLabel,
              icon: icon,
              color: buttonColor,
              onPressed: onConfirm,
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('Résidents — ${widget.residenceName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_rounded),
            onPressed: _showRuleDialog,
            tooltip: 'Enseigner règle',
          ),
          IconButton(
            icon: const Icon(Icons.campaign_rounded),
            onPressed: _showBroadcastDialog,
            tooltip: 'Annonce globale',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text(
          'Ajouter',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
      ),
      body: isLoading || isSending
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    isSending ? 'Envoi en cours...' : 'Chargement...',
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Stats bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: scheme.surface,
                  child: Row(
                    children: [
                      Icon(
                        Icons.people_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${residents.length} résidents',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        widget.residenceName,
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v.toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Rechercher nom, appt, téléphone...',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: scheme.primary,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.primary, width: 2),
                      ),
                    ),
                  ),
                ),
                // List
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 52,
                                color: scheme.onSurface.withValues(alpha: 0.2),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Aucun résident trouvé',
                                style: TextStyle(
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final r = _filtered[i];
                            return _ResidentCard(
                              resident: r,
                              scheme: scheme,
                              onEdit: () => _showEditDialog(resident: r),
                              onDelete: () => _showDeleteDialog(
                                r['unit'].toString(),
                                r['name'],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ── Resident Card ─────────────────────────────────────────────────────────────
class _ResidentCard extends StatelessWidget {
  final Map resident;
  final ColorScheme scheme;
  final VoidCallback onEdit, onDelete;

  const _ResidentCard({
    required this.resident,
    required this.scheme,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final unit = resident['unit']?.toString() ?? '?';
    final name = resident['name']?.toString() ?? '';
    final phone = (resident['phone']?.toString() ?? '').replaceAll(
      'whatsapp:',
      '',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                unit,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: unit.length > 3 ? 10 : 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.phone_rounded,
                      size: 12,
                      color: scheme.onSurface.withValues(alpha: 0.35),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Actions
          IconButton(
            icon: Icon(
              Icons.edit_rounded,
              size: 18,
              color: Colors.orange.shade600,
            ),
            tooltip: 'Modifier',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
            tooltip: 'Supprimer',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
