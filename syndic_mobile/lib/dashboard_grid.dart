import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'main.dart';
import 'api_service.dart';

class DashboardGridPage extends StatefulWidget {
  final String residenceId;
  final String residenceName;

  const DashboardGridPage({
    super.key,
    required this.residenceId,
    required this.residenceName,
  });

  @override
  State<DashboardGridPage> createState() => _DashboardGridPageState();
}

class _DashboardGridPageState extends State<DashboardGridPage> {
  List<dynamic> registeredResidents = [];
  List<dynamic> activeTickets = [];
  bool isLoading = true;
  late WebSocketChannel channel;

  // ── Theme helpers ───────────────────────────────────────────────────────────
  Color _urgencyColor(String? urgency, {double opacity = 1}) {
    switch (urgency) {
      case 'P0':
        return const Color(0xFFE53935).withValues(alpha: opacity);
      case 'P1':
        return const Color(0xFFFB8C00).withValues(alpha: opacity);
      default:
        return Colors.transparent;
    }
  }

  // ── Auth ────────────────────────────────────────────────────────────────────
  // Auth headers centralisés dans ApiService

  @override
  void initState() {
    super.initState();
    fetchData();
    _connectWebSocket();
  }

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  // ── WebSocket ───────────────────────────────────────────────────────────────
  int _wsRetryDelay = 2;

  void _connectWebSocket() {
    final wsScheme = BASE_URL.startsWith('https') ? 'wss' : 'ws';
    final domain = BASE_URL.replaceFirst(RegExp(r'https?://'), '');
    final wsUrl = Uri.parse('$wsScheme://$domain/ws');
    try {
      channel = WebSocketChannel.connect(wsUrl);
      _wsRetryDelay = 2; // reset on success
      channel.stream.listen(
        (message) {
          if (message == "REFRESH") fetchData();
        },
        onError: (e) {
          debugPrint("❌ WS Error: $e");
          _scheduleReconnect();
        },
        onDone: () => _scheduleReconnect(),
      );
    } catch (e) {
      debugPrint("❌ WS Exception: $e");
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    Future.delayed(Duration(seconds: _wsRetryDelay), () {
      if (mounted) {
        _wsRetryDelay = (_wsRetryDelay * 2).clamp(2, 30);
        _connectWebSocket();
      }
    });
  }

  // ── Fetch data ──────────────────────────────────────────────────────────────
  // Fix : _getAuthHeaders() était déjà défini mais non utilisé ici.
  // Les deux endpoints /api/grid-status et /api/residents requièrent
  // maintenant verify_token → on envoie le Bearer token sur les deux requêtes.
  // On les lance en parallèle avec Future.wait pour ne pas attendre l'une avant l'autre.
  Future<void> fetchData() async {
    try {
      final results = await Future.wait([
        ApiService.getResidents(widget.residenceId),
        ApiService.getGridStatus(widget.residenceId),
      ]);
      if (mounted) {
        setState(() {
          registeredResidents = results[0];
          activeTickets = results[1];
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erreur chargement: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Logic helpers ───────────────────────────────────────────────────────────
  Map<String, dynamic>? _getTicketForUnit(String unit) {
    try {
      return activeTickets.firstWhere((t) => t['unit'].toString() == unit);
    } catch (e) {
      return null;
    }
  }

  int get _pendingCount => activeTickets.length;
  int get _criticalCount =>
      activeTickets.where((t) => t['urgency_level'] == 'P0').length;

  // ── Quick-add resident from grid ────────────────────────────────────────────
  void _showAddResidentDialog({String? prefillUnit}) {
    final unitC = TextEditingController(text: prefillUnit ?? '');
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
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
            // Handle
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
            Text(
              'Ajouter un résident',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            _InputField(
              controller: unitC,
              label: 'Appartement',
              icon: Icons.home_rounded,
              scheme: scheme,
            ),
            const SizedBox(height: 12),
            _InputField(
              controller: nameC,
              label: 'Nom complet',
              icon: Icons.person_rounded,
              scheme: scheme,
            ),
            const SizedBox(height: 12),
            _InputField(
              controller: phoneC,
              label: 'Téléphone',
              icon: Icons.phone_rounded,
              scheme: scheme,
              hint: '+212XXXXXXXXX',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.person_add_rounded),
                label: const Text(
                  'Ajouter',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _addResident(
                    unitC.text.trim(),
                    nameC.text.trim(),
                    phoneC.text.trim(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addResident(String unit, String name, String phone) async {
    if (unit.isEmpty || name.isEmpty || phone.isEmpty) return;
    try {
      await ApiService.post('/api/residents', {
        "unit": unit,
        "name": name,
        "phone": phone,
        "residence_id": widget.residenceId,
      });
      fetchData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $name (Appt $unit) ajouté'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Erreur ajout: $e");
    }
  }

  // ── Validation dialog ───────────────────────────────────────────────────────
  void _showValidationDialog(Map<String, dynamic> ticket) {
    final iaController = TextEditingController(
      text: ticket['ia_response'] ?? '',
    );
    final urgency = ticket['urgency_level'] as String? ?? 'P?';
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
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _urgencyColor(urgency, opacity: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _urgencyColor(urgency, opacity: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: _urgencyColor(urgency),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        urgency,
                        style: TextStyle(
                          color: _urgencyColor(urgency),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Appt ${ticket['unit'] ?? '?'}  •  ${ticket['category'] ?? 'Autre'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Message
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                ticket['message'] ?? '',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: scheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
            if (ticket['assigned_to'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.person_pin_rounded,
                    size: 14,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Assigné à : ${ticket['assigned_to']}',
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            // IA response field
            TextField(
              controller: iaController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Réponse IA (modifiable)',
                alignLabelWithHint: true,
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.send_rounded),
                label: const Text(
                  'Valider & Envoyer WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await ApiService.post('/api/validate-ticket', {
                      "ticket_id": ticket['id'],
                      "text": iaController.text,
                      "phone": ticket['phone'],
                    });
                  } catch (e) {
                    debugPrint("Erreur validation: $e");
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(widget.residenceName),
        actions: [
          if (_criticalCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_criticalCount P0',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: fetchData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Stats bar ───────────────────────────────────────────────
                _StatsBar(
                  total: registeredResidents.length,
                  pending: _pendingCount,
                  critical: _criticalCount,
                  scheme: scheme,
                ),
                // ── Grid ────────────────────────────────────────────────────
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: fetchData,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.88,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      // +1 for the "add" card
                      itemCount: registeredResidents.length + 1,
                      itemBuilder: (context, index) {
                        // Last card = Add button
                        if (index == registeredResidents.length) {
                          return _AddUnitCard(
                            onTap: () => _showAddResidentDialog(),
                            scheme: scheme,
                          );
                        }
                        final resident = registeredResidents[index];
                        final unit = resident['unit'].toString();
                        final ticket = _getTicketForUnit(unit);
                        final hasAlert = ticket != null;
                        final urgency = ticket?['urgency_level'] as String?;
                        final isCritical = urgency == 'P0';

                        return _UnitCard(
                          unit: unit,
                          name: resident['name'] ?? '',
                          hasAlert: hasAlert,
                          isCritical: isCritical,
                          urgency: urgency,
                          onTap: () {
                            if (hasAlert) {
                              _showValidationDialog(ticket);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Appt $unit — R.A.S ✓'),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Stats Bar ─────────────────────────────────────────────────────────────────
class _StatsBar extends StatelessWidget {
  final int total, pending, critical;
  final ColorScheme scheme;
  const _StatsBar({
    required this.total,
    required this.pending,
    required this.critical,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: Border(
        bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.1)),
      ),
    ),
    child: Row(
      children: [
        _StatPill(
          icon: Icons.home_rounded,
          label: '$total appartements',
          color: scheme.primary,
          scheme: scheme,
        ),
        const SizedBox(width: 10),
        if (pending > 0)
          _StatPill(
            icon: Icons.hourglass_top_rounded,
            label: '$pending en attente',
            color: Colors.orange,
            scheme: scheme,
          ),
        if (critical > 0) ...[
          const SizedBox(width: 10),
          _StatPill(
            icon: Icons.warning_rounded,
            label: '$critical CRITIQUE',
            color: Colors.red,
            scheme: scheme,
          ),
        ],
      ],
    ),
  );
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final ColorScheme scheme;
  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

// ── Unit Card ─────────────────────────────────────────────────────────────────
class _UnitCard extends StatelessWidget {
  final String unit, name;
  final bool hasAlert, isCritical;
  final String? urgency;
  final VoidCallback onTap;

  const _UnitCard({
    required this.unit,
    required this.name,
    required this.hasAlert,
    required this.isCritical,
    required this.urgency,
    required this.onTap,
  });

  Color get _bg {
    if (!hasAlert) return Colors.transparent;
    return isCritical
        ? const Color(0xFFE53935).withValues(alpha: 0.1)
        : const Color(0xFFFB8C00).withValues(alpha: 0.08);
  }

  Color get _border {
    if (!hasAlert) return Colors.transparent;
    return isCritical
        ? const Color(0xFFE53935).withValues(alpha: 0.4)
        : const Color(0xFFFB8C00).withValues(alpha: 0.4);
  }

  Color get _iconColor {
    if (!hasAlert) return const Color(0xFF3D5AFE);
    return isCritical ? const Color(0xFFE53935) : const Color(0xFFFB8C00);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: hasAlert
              ? _bg
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasAlert ? _border : scheme.outline.withValues(alpha: 0.15),
            width: hasAlert ? 1.5 : 1,
          ),
          boxShadow: hasAlert
              ? [
                  BoxShadow(
                    color: _iconColor.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Stack(
              children: [
                Icon(
                  hasAlert ? Icons.warning_amber_rounded : Icons.home_rounded,
                  size: 28,
                  color: _iconColor,
                ),
                if (hasAlert && urgency != null)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        urgency!,
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          color: _iconColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              unit,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: hasAlert ? _iconColor : scheme.onSurface,
              ),
            ),
            Text(
              _shortName(name),
              style: TextStyle(
                fontSize: 9,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _shortName(String name) {
    if (name.isEmpty) return '';
    final parts = name.split(' ');
    return parts.length > 1 ? '${parts.first} ${parts.last[0]}.' : parts.first;
  }
}

// ── Add Unit Card ─────────────────────────────────────────────────────────────
class _AddUnitCard extends StatelessWidget {
  final VoidCallback onTap;
  final ColorScheme scheme;
  const _AddUnitCard({required this.onTap, required this.scheme});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.3),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_circle_outline_rounded,
            size: 28,
            color: scheme.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 6),
          Text(
            'Ajouter',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Input Field helper ────────────────────────────────────────────────────────
class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final ColorScheme scheme;
  final String? hint;
  final TextInputType? keyboardType;

  const _InputField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.scheme,
    this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
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
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
  );
}
