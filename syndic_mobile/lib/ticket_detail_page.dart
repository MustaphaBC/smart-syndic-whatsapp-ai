import 'package:flutter/material.dart';
import 'api_service.dart';

class TicketDetailPage extends StatefulWidget {
  final int ticketId;
  final String? previewUnit;
  final String? previewUrgency;

  const TicketDetailPage({
    super.key,
    required this.ticketId,
    this.previewUnit,
    this.previewUrgency,
  });

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  Map<String, dynamic>? ticket;
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final data = await ApiService.getTicketDetail(widget.ticketId);
      if (mounted) {
        setState(() {
          ticket = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Erreur: $e';
          isLoading = false;
        });
      }
    }
  }

  // ── Couleurs ──────────────────────────────────────────────────────────────
  Color _urgencyColor(String? level) {
    switch (level) {
      case 'P0':
        return const Color(0xFFE53935);
      case 'P1':
        return const Color(0xFFFB8C00);
      case 'P2':
        return const Color(0xFF43A047);
      case 'P3':
        return const Color(0xFF1E88E5);
      default:
        return Colors.grey;
    }
  }

  Color _statusColor(String? status) {
    if (status == 'validated') return const Color(0xFF00C853);
    if (status == 'pending') return const Color(0xFFFF6D00);
    return Colors.grey;
  }

  IconData _categoryIcon(String? category) {
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
        return Icons.elevator_rounded;
      case 'INONDATION_MAJEURE':
        return Icons.flood_rounded;
      case 'SÉCURITÉ':
        return Icons.shield_rounded;
      case 'Administratif':
        return Icons.description_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _sentimentEmoji(String? sentiment) {
    if (sentiment == 'Positif') return '😊';
    if (sentiment == 'Négatif') return '😤';
    return '😐';
  }

  String _languageLabel(String? lang) {
    switch (lang) {
      case 'fr':
        return '🇫🇷 Français';
      case 'ar':
        return '🇲🇦 Arabe';
      case 'en':
        return '🇬🇧 Anglais';
      default:
        return lang ?? 'Inconnu';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: scheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Ticket #${widget.ticketId}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: scheme.primary),
            onPressed: () {
              setState(() => isLoading = true);
              _fetchDetail();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? _buildError(scheme)
          : _buildContent(scheme),
    );
  }

  Widget _buildError(ColorScheme scheme) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline_rounded, size: 64, color: scheme.error),
        const SizedBox(height: 16),
        Text(error!, style: TextStyle(color: scheme.error)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Réessayer'),
          onPressed: _fetchDetail,
        ),
      ],
    ),
  );

  Widget _buildContent(ColorScheme scheme) {
    final t = ticket!;
    final urgency = t['urgency_level'] as String?;
    final status = t['status'] as String?;
    final urgColor = _urgencyColor(urgency);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero card ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  urgColor.withValues(alpha: 0.15),
                  urgColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: urgColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: urgColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _categoryIcon(t['category']),
                    color: urgColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Chip(
                            label: urgency ?? 'P?',
                            color: urgColor,
                            textColor: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          _Chip(
                            label: status == 'validated'
                                ? '✓ Résolu'
                                : '⏳ En attente',
                            color: _statusColor(status),
                            textColor: Colors.white,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t['category'] ?? 'Autre',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Appartement ${t['unit'] ?? '?'}  •  ${t['datetime'] != null ? _formatDate(t['datetime']) : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Metadata row ─────────────────────────────────────────────────
          Row(
            children: [
              _MetaChip(
                icon: Icons.person_pin_rounded,
                label: t['assigned_to'] ?? 'Syndic',
                scheme: scheme,
              ),
              const SizedBox(width: 8),
              _MetaChip(
                icon: Icons.translate_rounded,
                label: _languageLabel(t['language']),
                scheme: scheme,
              ),
              const SizedBox(width: 8),
              _MetaChip(
                icon: Icons.sentiment_neutral_rounded,
                label:
                    '${_sentimentEmoji(t['sentiment'])} ${t['sentiment'] ?? 'Neutre'}',
                scheme: scheme,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MetaChip(
                icon: Icons.timer_rounded,
                label: 'SLA: ${t['sla_minutes']} min',
                scheme: scheme,
              ),
              const SizedBox(width: 8),
              if (t['sla_respected'] != null)
                _MetaChip(
                  icon: t['sla_respected']
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  label: t['sla_respected'] ? 'SLA respecté' : 'SLA dépassé',
                  scheme: scheme,
                  color: t['sla_respected'] ? Colors.green : Colors.red,
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Message original ─────────────────────────────────────────────
          _SectionHeader(label: 'MESSAGE DU RÉSIDENT', scheme: scheme),
          const SizedBox(height: 8),
          _ContentCard(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: scheme.primary,
            content: t['text'] ?? '',
            scheme: scheme,
          ),
          const SizedBox(height: 16),

          // ── Réponse IA ───────────────────────────────────────────────────
          _SectionHeader(label: 'ANALYSE & RÉPONSE IA', scheme: scheme),
          const SizedBox(height: 8),
          _ContentCard(
            icon: Icons.smart_toy_rounded,
            iconColor: const Color(0xFF7C4DFF),
            content: t['ia_response'] ?? 'Aucune réponse IA',
            scheme: scheme,
            accentColor: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
          ),

          // ── Réponse finale ───────────────────────────────────────────────
          if (t['final_response'] != null) ...[
            const SizedBox(height: 16),
            _SectionHeader(
              label: 'RÉPONSE ENVOYÉE AU RÉSIDENT',
              scheme: scheme,
            ),
            const SizedBox(height: 8),
            _ContentCard(
              icon: Icons.send_rounded,
              iconColor: Colors.green,
              content: t['final_response'],
              scheme: scheme,
              accentColor: Colors.green.withValues(alpha: 0.08),
            ),
          ],
          const SizedBox(height: 20),

          // ── Timeline ─────────────────────────────────────────────────────
          _SectionHeader(label: 'CHRONOLOGIE', scheme: scheme),
          const SizedBox(height: 12),
          _Timeline(ticket: t, urgColor: urgColor, scheme: scheme),
          const SizedBox(height: 20),

          // ── Infos techniques ─────────────────────────────────────────────
          _SectionHeader(label: 'INFORMATIONS TECHNIQUES', scheme: scheme),
          const SizedBox(height: 8),
          _InfoTable(
            rows: [
              ['ID Message', t['message_id'] ?? '-'],
              ['Résidence', t['residence_id'] ?? '-'],
              [
                'Média',
                t['has_media'] == true ? (t['media_type'] ?? 'oui') : 'Non',
              ],
            ],
            scheme: scheme,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return iso;
    }
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  const _Chip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: textColor,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme scheme;
  final Color? color;
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.scheme,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: (color ?? scheme.primary).withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? scheme.primary),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? scheme.primary,
          ),
        ),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final ColorScheme scheme;
  const _SectionHeader({required this.label, required this.scheme});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      color: scheme.primary,
    ),
  );
}

class _ContentCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String content;
  final ColorScheme scheme;
  final Color? accentColor;
  const _ContentCard({
    required this.icon,
    required this.iconColor,
    required this.content,
    required this.scheme,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:
          accentColor ?? scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: iconColor.withValues(alpha: 0.2), width: 1),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: scheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Timeline extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final Color urgColor;
  final ColorScheme scheme;
  const _Timeline({
    required this.ticket,
    required this.urgColor,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final steps = [
      _TimelineStep(
        icon: Icons.inbox_rounded,
        label: 'Message reçu',
        subtitle: ticket['datetime'] != null
            ? _fmt(ticket['datetime'])
            : 'Inconnu',
        color: scheme.primary,
        done: true,
      ),
      _TimelineStep(
        icon: Icons.smart_toy_rounded,
        label: 'Analysé par l\'IA',
        subtitle:
            '${ticket['urgency_level'] ?? '?'} • ${ticket['category'] ?? 'Autre'}',
        color: const Color(0xFF7C4DFF),
        done: true,
      ),
      _TimelineStep(
        icon: Icons.person_pin_rounded,
        label: 'Assigné',
        subtitle: ticket['assigned_to'] ?? 'Syndic',
        color: const Color(0xFF0288D1),
        done: true,
      ),
      _TimelineStep(
        icon: Icons.check_circle_rounded,
        label: 'Résolu',
        subtitle: ticket['validation_date'] != null
            ? _fmt(ticket['validation_date'])
            : 'En attente…',
        color: Colors.green,
        done: ticket['status'] == 'validated',
      ),
    ];

    return Column(
      children: steps.asMap().entries.map((e) {
        final isLast = e.key == steps.length - 1;
        final step = e.value;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: step.done
                        ? step.color.withValues(alpha: 0.15)
                        : scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: step.done ? step.color : scheme.outline,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    step.icon,
                    size: 18,
                    color: step.done ? step.color : scheme.outline,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 36,
                    color: step.done
                        ? step.color.withValues(alpha: 0.3)
                        : scheme.outline.withValues(alpha: 0.3),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: step.done
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    Text(
                      step.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return iso;
    }
  }
}

class _TimelineStep {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool done;
  const _TimelineStep({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.done,
  });
}

class _InfoTable extends StatelessWidget {
  final List<List<String>> rows;
  final ColorScheme scheme;
  const _InfoTable({required this.rows, required this.scheme});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: rows.asMap().entries.map((e) {
        final isLast = e.key == rows.length - 1;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(
                      color: scheme.outline.withValues(alpha: 0.15),
                    ),
                  ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  e.value[0],
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  e.value[1],
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ),
  );
}
