import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_theme.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});
  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic> data = {};
  Map<String, dynamic> satisfactionData = {};
  bool isLoading = true;
  int _selectedDays = 30;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => isLoading = true);
    try {
      // Appels parallèles : analytics + satisfaction
      final results = await Future.wait([
        ApiService.getAnalytics(_selectedDays),
        ApiService.getSatisfactionStats(),
      ]);

      if (mounted) {
        setState(() {
          data = results[0];
          satisfactionData = results[1];
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erreur analytics: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Analyse & Pilotage'),
        actions: [
          // ── Filtre période ──────────────────────────────────────────────
          PopupMenuButton<int>(
            icon: const Icon(Icons.date_range_rounded),
            tooltip: 'Période',
            initialValue: _selectedDays,
            onSelected: (days) {
              if (days != _selectedDays) {
                setState(() => _selectedDays = days);
                _fetch();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 7, child: Text('7 derniers jours')),
              const PopupMenuItem(value: 30, child: Text('30 derniers jours')),
              const PopupMenuItem(value: 90, child: Text('90 derniers jours')),
              const PopupMenuItem(value: 0, child: Text('Tout l\'historique')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetch,
            tooltip: 'Actualiser',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.dashboard_rounded, size: 18),
              text: 'Tableau de bord',
            ),
            Tab(
              icon: Icon(Icons.donut_large_rounded, size: 18),
              text: 'Catégories',
            ),
            Tab(
              icon: Icon(Icons.trending_up_rounded, size: 18),
              text: 'Tendances',
            ),
          ],
        ),
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Chargement des données...',
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                _DashboardTab(data: data, satisfactionData: satisfactionData),
                _CategoriesTab(data: data),
                _TrendsTab(data: data),
              ],
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — TABLEAU DE BORD
// ══════════════════════════════════════════════════════════════════════════════
class _DashboardTab extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic> satisfactionData;
  const _DashboardTab({required this.data, required this.satisfactionData});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = data['summary'] as Map? ?? {};
    final sla = data['sla'] as Map? ?? {};
    final byStatus = data['by_status'] as List? ?? [];
    final total = (summary['total'] ?? 1) as int;

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── OVERVIEW HERO ───────────────────────────────────────────────
          _HeroSummaryCard(summary: summary),
          const SizedBox(height: 20),

          // ── KPI GRID ─────────────────────────────────────────────────────
          const SectionHeader(label: 'Indicateurs clés'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _KpiCard(
                label: 'Total Tickets',
                value: '${summary['total'] ?? 0}',
                icon: Icons.confirmation_number_rounded,
                color: scheme.primary,
              ),
              _KpiCard(
                label: 'Tickets Urgents',
                value: '${summary['urgent'] ?? 0}',
                icon: Icons.warning_amber_rounded,
                color: AppColors.p1,
                subtitle: _pct(summary['urgent'], total),
              ),
              _KpiCard(
                label: 'P0 Critiques',
                value: '${summary['p0'] ?? 0}',
                icon: Icons.local_fire_department_rounded,
                color: AppColors.p0,
              ),
              _KpiCard(
                label: 'P1 Urgents',
                value: '${summary['p1'] ?? 0}',
                icon: Icons.bolt_rounded,
                color: AppColors.p1,
              ),
              _KpiCard(
                label: 'Résolus',
                value: '${summary['validated'] ?? 0}',
                icon: Icons.check_circle_rounded,
                color: AppColors.p2,
                subtitle: _pct(summary['validated'], total),
              ),
              _KpiCard(
                label: 'En Attente',
                value: '${summary['pending'] ?? 0}',
                icon: Icons.hourglass_top_rounded,
                color: Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── SLA PERFORMANCE ─────────────────────────────────────────────
          const SectionHeader(label: 'Performance SLA'),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                _SlaRow(
                  label: 'P0  5 min',
                  respected: sla['p0_respected'],
                  total: sla['p0_total'],
                  color: AppColors.p0,
                ),
                _Divider(),
                _SlaRow(
                  label: 'P1  30 min',
                  respected: sla['p1_respected'],
                  total: sla['p1_total'],
                  color: AppColors.p1,
                ),
                _Divider(),
                _SlaRow(
                  label: 'P2  4 h',
                  respected: sla['p2_respected'],
                  total: sla['p2_total'],
                  color: AppColors.p2,
                ),
                _Divider(),
                _SlaRow(
                  label: 'P3  24 h',
                  respected: sla['p3_respected'],
                  total: sla['p3_total'],
                  color: AppColors.p3,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── TOP INTERVENANTS ─────────────────────────────────────────────
          const SectionHeader(label: 'Top intervenants'),
          const SizedBox(height: 12),
          _IntervenantsCard(byAssignee: data['by_assignee'] as List? ?? []),
          const SizedBox(height: 24),

          // ── SATISFACTION RÉSIDENTE ────────────────────────────────────────
          const SectionHeader(label: 'Satisfaction résidente'),
          const SizedBox(height: 12),
          _SatisfactionCard(satData: satisfactionData),
          const SizedBox(height: 24),

          // ── STATUS BREAKDOWN ─────────────────────────────────────────────
          const SectionHeader(label: 'Répartition par statut'),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: (byStatus).map<Widget>((item) {
                final label = item['status'] as String? ?? '';
                final count = (item['count'] ?? 0) as int;
                final pct = total > 0 ? count / total : 0.0;
                final color = label == 'validated'
                    ? AppColors.p2
                    : label == 'pending'
                    ? AppColors.pending
                    : Colors.grey;
                final text = label == 'validated'
                    ? 'Résolus'
                    : label == 'pending'
                    ? 'En attente'
                    : label;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                text,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '$count  (${(pct * 100).toStringAsFixed(1)}%)',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 8,
                          backgroundColor: color.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // ── RÉSIDENCES TABLE ─────────────────────────────────────────────
          const SectionHeader(label: 'Tickets par résidence'),
          const SizedBox(height: 12),
          _ResidencesTable(data: data),
        ],
      ),
    );
  }
}

// ── Hero summary card ─────────────────────────────────────────────────────────
class _HeroSummaryCard extends StatelessWidget {
  final Map summary;
  const _HeroSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = (summary['total'] ?? 0) as int;
    final validated = (summary['validated'] ?? 0) as int;
    final p0 = (summary['p0'] ?? 0) as int;
    final rate = total > 0 ? validated / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            scheme.primary.withBlue(
              ((scheme.primary.b * 255.0).round() + 40).clamp(0, 255),
            ),
          ],
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Taux de résolution',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(rate * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$validated résolu(s) sur $total tickets',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _HeroStat(label: 'Total', value: '$total', color: Colors.white),
              const SizedBox(height: 8),
              _HeroStat(
                label: 'P0 Critiques',
                value: '$p0',
                color: p0 > 0 ? const Color(0xFFFFCDD2) : Colors.white70,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _HeroStat({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(
        label,
        style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10),
      ),
    ],
  );
}

// ── KPI Card ─────────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
    );
  }
}

// ── SLA Row ───────────────────────────────────────────────────────────────────
class _SlaRow extends StatelessWidget {
  final String label;
  final dynamic respected, total;
  final Color color;
  const _SlaRow({
    required this.label,
    this.respected,
    this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final r = (respected ?? 0) as int;
    final t = (total ?? 0) as int;
    final pct = t > 0 ? r / t : 0.0;
    final pctColor = pct >= 0.8
        ? AppColors.p2
        : pct >= 0.5
        ? AppColors.p1
        : AppColors.p0;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 10,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(pctColor),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$r/$t tickets  •  ${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: pctColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: pctColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Residences table ──────────────────────────────────────────────────────────
class _ResidencesTable extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ResidencesTable({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final residences = data['by_residence'] as List? ?? [];
    if (residences.isEmpty) {
      return const _EmptyState(msg: 'Pas de données résidences.');
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Résidence',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                _HeaderCell('Tickets'),
                _HeaderCell('Urgents'),
              ],
            ),
          ),
          ...residences.asMap().entries.map((e) {
            final r = e.value;
            final isLast = e.key == residences.length - 1;
            final urgent = (r['urgent'] ?? 0) as int;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.08),
                        ),
                      ),
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(16))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          r['residence_id']
                                  ?.replaceAll('RES_', '')
                                  .replaceAll('_', ' ') ??
                              '',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Center(
                      child: Text(
                        '${r['total']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Center(
                      child: urgent > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.p1.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$urgent',
                                style: const TextStyle(
                                  color: AppColors.p1,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : Text(
                              '0',
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.3),
                                fontSize: 13,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 70,
    child: Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — CATÉGORIES
// ══════════════════════════════════════════════════════════════════════════════
class _CategoriesTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CategoriesTab({required this.data});

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final scheme = Theme.of(context).colorScheme;
    final categories = data['by_category'] as List? ?? [];
    final sentiments = data['by_sentiment'] as List? ?? [];
    final byUrgency = data['urgency_by_category'] as List? ?? [];
    final total = (data['summary']?['total'] ?? 1) as int;

    if (categories.isEmpty) {
      return const _EmptyState(msg: 'Pas encore de données de catégories.');
    }
    final maxCount = categories.fold<int>(
      0,
      (p, e) => ((e['count'] as int?) ?? 0) > p ? (e['count'] as int) : p,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Volumes ─────────────────────────────────────────────────────────
        const SectionHeader(label: 'Volume par catégorie'),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: categories.map<Widget>((cat) {
              final name = cat['category'] as String? ?? 'Autre';
              final count = (cat['count'] ?? 0) as int;
              final pct = maxCount > 0 ? count / maxCount : 0.0;
              final color = AppColors.categoryColor(name);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        AppColors.categoryIcon(name),
                        color: color,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 92,
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 14,
                          backgroundColor: color.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(
                            color.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: color,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),

        // ── Urgence par catégorie ────────────────────────────────────────────
        const SectionHeader(label: 'Niveaux d\'urgence par catégorie'),
        const SizedBox(height: 12),
        _UrgencyByCategoryCard(data: byUrgency),
        const SizedBox(height: 24),

        // ── Sentiments ──────────────────────────────────────────────────────
        const SectionHeader(label: 'Analyse des sentiments'),
        const SizedBox(height: 12),
        AppCard(
          child: sentiments.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Pas de données'),
                  ),
                )
              : Column(
                  children: sentiments.map<Widget>((s) {
                    final label = s['sentiment'] as String? ?? '';
                    final count = (s['count'] ?? 0) as int;
                    final pct = total > 0 ? count / total : 0.0;
                    final color = label == 'Positif'
                        ? AppColors.p2
                        : label == 'Négatif'
                        ? AppColors.p0
                        : Colors.blueGrey;
                    final icon = label == 'Positif'
                        ? Icons.sentiment_satisfied_alt_rounded
                        : label == 'Négatif'
                        ? Icons.sentiment_very_dissatisfied_rounded
                        : Icons.sentiment_neutral_rounded;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 72,
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: color,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 10,
                                backgroundColor: color.withValues(alpha: 0.08),
                                valueColor: AlwaysStoppedAnimation(color),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$count  (${(pct * 100).toStringAsFixed(0)}%)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: color,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _UrgencyByCategoryCard extends StatelessWidget {
  final List data;
  const _UrgencyByCategoryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (data.isEmpty) return const _EmptyState(msg: 'Pas de données.');
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Catégorie',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final l in ['P0', 'P1', 'P2', 'P3'])
                  SizedBox(
                    width: 44,
                    child: Center(
                      child: Text(
                        l,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.urgencyColor(l),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...data.asMap().entries.map((e) {
            final row = e.value;
            final isLast = e.key == data.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.08),
                        ),
                      ),
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(16))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          AppColors.categoryIcon(row['category']),
                          size: 14,
                          color: AppColors.categoryColor(row['category']),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            row['category'] ?? '',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final l in ['p0', 'p1', 'p2', 'p3'])
                    SizedBox(
                      width: 44,
                      child: Center(
                        child: _urgencyCell(row[l] ?? 0, l.toUpperCase()),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _urgencyCell(int count, String level) {
    if (count == 0) {
      return Text(
        '—',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.urgencyColor(level).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.urgencyColor(level),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 — TENDANCES
// ══════════════════════════════════════════════════════════════════════════════
class _TrendsTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TrendsTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daily = data['daily_trend'] as List? ?? [];
    final pending = data['pending_tickets'] as List? ?? [];

    if (daily.isEmpty) {
      return const _EmptyState(msg: 'Pas encore de données de tendances.');
    }
    final maxVal = daily.fold<int>(
      0,
      (p, e) => ((e['total'] as int?) ?? 0) > p ? (e['total'] as int) : p,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Bar Chart ────────────────────────────────────────────────────────
        const SectionHeader(label: 'Activité quotidienne (14 jours)'),
        const SizedBox(height: 12),
        AppCard(
          child: SizedBox(
            height: 200,
            child: _BarChart(daily: daily, maxVal: maxVal, scheme: scheme),
          ),
        ),
        const SizedBox(height: 24),

        // ── Urgency by assignee ───────────────────────────────────────────────
        if (data['by_assignee'] != null) ...[
          const SectionHeader(label: 'Charge par intervenant'),
          const SizedBox(height: 12),
          _AssigneeCard(data: data['by_assignee'] as List),
          const SizedBox(height: 24),
        ],

        // ── Daily detail table ────────────────────────────────────────────────
        const SectionHeader(label: 'Détail quotidien'),
        const SizedBox(height: 12),
        _DailyTable(daily: daily),
        const SizedBox(height: 24),

        // ── Pending list ──────────────────────────────────────────────────────
        const SectionHeader(label: 'Tickets en attente de validation'),
        const SizedBox(height: 12),
        _PendingList(pending: pending),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  final List daily;
  final int maxVal;
  final ColorScheme scheme;
  const _BarChart({
    required this.daily,
    required this.maxVal,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    if (maxVal == 0) return const Center(child: Text('Pas de données'));
    final days = daily.take(14).toList();
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: days.map<Widget>((d) {
              final total = (d['total'] ?? 0) as int;
              final p0Count = (d['p0'] ?? 0) as int;
              final barH = maxVal > 0 ? total / maxVal : 0.0;
              final date = (d['date'] ?? '').toString();
              final dayStr = date.length >= 5 ? date.substring(5) : date;
              final barColor = p0Count > 0
                  ? AppColors.p0
                  : scheme.primary.withValues(alpha: 0.7);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (total > 0)
                        Text(
                          '$total',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        height: 155 * barH,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dayStr,
                        style: TextStyle(
                          fontSize: 8,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _AssigneeCard extends StatelessWidget {
  final List data;
  const _AssigneeCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: data.asMap().entries.map((e) {
          final row = e.value;
          final isLast = e.key == data.length - 1;
          final done = (row['done'] ?? 0) as int;
          final tot = (row['total'] ?? 1) as int;
          final pct = tot > 0 ? done / tot : 0.0;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: scheme.outline.withValues(alpha: 0.08),
                      ),
                    ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.person_pin_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['assigned_to'] ?? '–',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            pct >= 0.8 ? AppColors.p2 : scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$done/$tot',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${(pct * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DailyTable extends StatelessWidget {
  final List daily;
  const _DailyTable({required this.daily});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Date',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final h in ['Total', 'P0', 'P1', 'Résolus'])
                  SizedBox(
                    width: 52,
                    child: Center(
                      child: Text(
                        h,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...daily.take(14).toList().asMap().entries.map((e) {
            final d = e.value;
            final isLast = e.key == daily.take(14).length - 1;
            final p0c = (d['p0'] ?? 0) as int;
            final p1c = (d['p1'] ?? 0) as int;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.07),
                        ),
                      ),
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(16))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      d['date'] ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Center(
                      child: Text(
                        '${d['total']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Center(
                      child: p0c > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.p0.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$p0c',
                                style: const TextStyle(
                                  color: AppColors.p0,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          : Text(
                              '—',
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.3),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Center(
                      child: p1c > 0
                          ? Text(
                              '$p1c',
                              style: const TextStyle(
                                color: AppColors.p1,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            )
                          : Text(
                              '—',
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.3),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Center(
                      child: Text(
                        '${d['validated'] ?? 0}',
                        style: const TextStyle(
                          color: AppColors.p2,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PendingList extends StatelessWidget {
  final List pending;
  const _PendingList({required this.pending});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (pending.isEmpty) {
      return AppCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.p2, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Aucun ticket en attente 🎉',
              style: TextStyle(
                color: AppColors.p2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: pending.map<Widget>((t) {
        final urgency = t['urgency_level'] as String? ?? 'P3';
        final color = AppColors.urgencyColor(urgency);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    urgency,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appt ${t['unit'] ?? '?'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t['message'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                t['date'] ?? '',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGET — TOP INTERVENANTS
// ══════════════════════════════════════════════════════════════════════════════
class _IntervenantsCard extends StatelessWidget {
  final List byAssignee;
  const _IntervenantsCard({required this.byAssignee});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (byAssignee.isEmpty) {
      return const _EmptyState(msg: 'Aucune donnée d\'intervenants');
    }

    return AppCard(
      child: Column(
        children: byAssignee.take(6).toList().asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value as Map;
          final name = item['assigned_to'] as String? ?? 'Inconnu';
          final total = (item['total'] as int?) ?? 0;
          final done = (item['done'] as int?) ?? 0;
          final pct = total > 0 ? done / total : 0.0;
          final color = [
            AppColors.primary,
            AppColors.p1,
            AppColors.p2,
            AppColors.p3,
            AppColors.ascenseur,
            AppColors.administratif,
          ][i % 6];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '$done/$total',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: color.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 5,
                  ),
                ),
                if (i < byAssignee.length - 1 && i < 5) ...[
                  const SizedBox(height: 4),
                  Divider(
                    height: 1,
                    color: scheme.outline.withValues(alpha: 0.08),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGET — SATISFACTION RÉSIDENTE
// ══════════════════════════════════════════════════════════════════════════════
class _SatisfactionCard extends StatelessWidget {
  final Map<String, dynamic> satData;
  const _SatisfactionCard({required this.satData});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (satData.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            Icon(
              Icons.sentiment_satisfied_alt_rounded,
              color: scheme.onSurface.withValues(alpha: 0.3),
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              'Aucune donnée de satisfaction disponible',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    final satisfied = (satData['satisfied'] as int?) ?? 0;
    final notSatisfied = (satData['not_satisfied'] as int?) ?? 0;
    final awaiting = (satData['awaiting'] as int?) ?? 0;
    final rate = satData['satisfaction_rate'] as double?;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Taux global
          Row(
            children: [
              Icon(
                rate != null && rate >= 70
                    ? Icons.sentiment_very_satisfied_rounded
                    : Icons.sentiment_dissatisfied_rounded,
                color: rate != null && rate >= 70 ? AppColors.p2 : AppColors.p0,
                size: 28,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rate != null
                        ? '$rate% de satisfaction'
                        : 'En attente de données',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${satisfied + notSatisfied} réponses reçues',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Barre de satisfaction
          if (satisfied + notSatisfied > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: satisfied / (satisfied + notSatisfied),
                backgroundColor: AppColors.p0.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.p2),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Détail
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SatChip(
                label: 'Satisfaits',
                value: satisfied,
                color: AppColors.p2,
              ),
              _SatChip(
                label: 'Insatisfaits',
                value: notSatisfied,
                color: AppColors.p0,
              ),
              _SatChip(
                label: 'En attente',
                value: awaiting,
                color: AppColors.p3,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _SatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
      Text(
        label,
        style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
      ),
    ],
  );
}

// ── Shared helpers ────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String msg;
  const _EmptyState({required this.msg});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bar_chart_rounded,
            size: 56,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            msg,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
    height: 16,
    thickness: 1,
    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
  );
}

String _pct(dynamic num, dynamic denom) {
  final n = (num ?? 0) as int;
  final d = (denom ?? 1) as int;
  if (d == 0) return '';
  return '${(n / d * 100).toStringAsFixed(1)}%';
}
