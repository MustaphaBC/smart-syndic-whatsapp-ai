import 'package:flutter/material.dart';
import 'api_service.dart';
import 'ticket_detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<dynamic> _allHistory = [];
  List<dynamic> _filtered = [];
  bool _isLoading = true;

  // ── Filters ─────────────────────────────────────────────────────────────────
  String _searchQuery = '';
  String _urgencyFilter = 'Tout';
  String _statusFilter = 'Tout';
  String _categoryFilter = 'Tout';

  final List<String> _urgencyOptions = ['Tout', 'P0', 'P1', 'P2', 'P3'];
  final List<String> _statusOptions = ['Tout', 'pending', 'validated'];

  // ── Pagination ──────────────────────────────────────────────────────────────
  int _currentOffset = 0;
  bool _hasMore = true;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _fetchHistory();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      _loadMore();
    }
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getHistory();
      if (mounted) {
        setState(() {
          _allHistory = data;
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      debugPrint("Erreur historique: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Filter logic ─────────────────────────────────────────────────────────────
  void _applyFilters() {
    setState(() {
      _filtered = _allHistory.where((item) {
        // Search
        if (_searchQuery.isNotEmpty) {
          final msg = (item['message'] ?? '').toString().toLowerCase();
          final unit = (item['unit'] ?? '').toString().toLowerCase();
          final cat = (item['category'] ?? '').toString().toLowerCase();
          if (!msg.contains(_searchQuery.toLowerCase()) &&
              !unit.contains(_searchQuery.toLowerCase()) &&
              !cat.contains(_searchQuery.toLowerCase())) {
            return false;
          }
        }
        // Urgency
        if (_urgencyFilter != 'Tout' && item['urgency'] != _urgencyFilter) {
          return false;
        }
        // Status
        if (_statusFilter != 'Tout' && item['status'] != _statusFilter) {
          return false;
        }
        // Category
        if (_categoryFilter != 'Tout' && item['category'] != _categoryFilter) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore) return;

    try {
      final newItems = await ApiService.getHistory(
        limit: 100,
        days: 30,
        offset: _currentOffset,
      );
      if (mounted) {
        setState(() {
          _allHistory.addAll(newItems);
          _currentOffset += newItems.length;
          _hasMore = newItems.length == 100;
        });
        _applyFilters();
      }
    } catch (e) {
      debugPrint("Erreur chargement plus: $e");
    }
  }

  List<String> get _categoryOptions {
    final cats =
        _allHistory
            .map((item) => item['category']?.toString() ?? 'Autre')
            .toSet()
            .toList()
          ..sort();
    return ['Tout', ...cats];
  }

  // ── Colors ───────────────────────────────────────────────────────────────────
  Color _urgencyColor(String? urgency) {
    switch (urgency) {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Historique'),
            const SizedBox(width: 8),
            if (!_isLoading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_filtered.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Search bar ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    onChanged: (v) {
                      _searchQuery = v;
                      _applyFilters();
                    },
                    decoration: InputDecoration(
                      hintText: 'Rechercher message, appt, catégorie...',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: scheme.primary,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchQuery = '';
                                _applyFilters();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                const SizedBox(height: 10),

                // ── Urgency filter chips ─────────────────────────────────────
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: _urgencyOptions.map((opt) {
                      final isSelected = _urgencyFilter == opt;
                      final color = opt == 'Tout'
                          ? scheme.primary
                          : _urgencyColor(opt);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            opt,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : color,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _urgencyFilter = opt);
                            _applyFilters();
                          },
                          backgroundColor: color.withValues(alpha: 0.08),
                          selectedColor: color,
                          checkmarkColor: Colors.white,
                          side: BorderSide(
                            color: isSelected
                                ? color
                                : color.withValues(alpha: 0.3),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Status + Category filters ────────────────────────────────
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      // Status dropdown
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterDropdown(
                          value: _statusFilter,
                          items: _statusOptions,
                          icon: Icons.circle_outlined,
                          label: 'Statut',
                          scheme: scheme,
                          onChanged: (v) {
                            setState(() => _statusFilter = v!);
                            _applyFilters();
                          },
                        ),
                      ),
                      // Category dropdown
                      _FilterDropdown(
                        value: _categoryFilter,
                        items: _categoryOptions,
                        icon: Icons.category_rounded,
                        label: 'Catégorie',
                        scheme: scheme,
                        onChanged: (v) {
                          setState(() => _categoryFilter = v!);
                          _applyFilters();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ── Results ──────────────────────────────────────────────────
                Expanded(
                  child: _filtered.isEmpty
                      ? _buildEmpty(scheme)
                      : RefreshIndicator(
                          onRefresh: _fetchHistory,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) => _TicketCard(
                              item: _filtered[i],
                              urgencyColor: _urgencyColor(
                                _filtered[i]['urgency'],
                              ),
                              statusColor: _statusColor(_filtered[i]['status']),
                              categoryIcon: _categoryIcon(
                                _filtered[i]['category'],
                              ),
                              scheme: scheme,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TicketDetailPage(
                                    ticketId: _filtered[i]['id'],
                                    previewUnit: _filtered[i]['unit'],
                                    previewUrgency: _filtered[i]['urgency'],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(ColorScheme scheme) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.inbox_rounded,
          size: 64,
          color: scheme.onSurface.withValues(alpha: 0.2),
        ),
        const SizedBox(height: 12),
        Text(
          'Aucun ticket trouvé',
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.4),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Essayez de modifier les filtres',
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.3),
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

// ── Ticket Card ───────────────────────────────────────────────────────────────
class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Color urgencyColor, statusColor;
  final IconData categoryIcon;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _TicketCard({
    required this.item,
    required this.urgencyColor,
    required this.statusColor,
    required this.categoryIcon,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final urgency = item['urgency'] as String? ?? 'P?';
    final status = item['status'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: urgencyColor.withValues(alpha: 0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // ── Icon column ───────────────────────────────────────────────
              Column(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: urgencyColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(categoryIcon, color: urgencyColor, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: urgencyColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      urgency,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // ── Content ───────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['category'] ?? 'Autre',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          item['date'] ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item['message'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                status == 'validated'
                                    ? Icons.check_circle_rounded
                                    : Icons.hourglass_top_rounded,
                                size: 10,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                status == 'validated' ? 'Résolu' : 'En attente',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (item['unit'] != null)
                          Text(
                            'Appt ${item['unit']}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        if (item['assigned_to'] != null) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.person_pin_rounded,
                            size: 11,
                            color: scheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              item['assigned_to'],
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurface.withValues(alpha: 0.4),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filter Dropdown ───────────────────────────────────────────────────────────
class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final IconData icon;
  final String label;
  final ColorScheme scheme;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.icon,
    required this.label,
    required this.scheme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    decoration: BoxDecoration(
      color: value != 'Tout'
          ? scheme.primary.withValues(alpha: 0.1)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: value != 'Tout'
            ? scheme.primary.withValues(alpha: 0.4)
            : scheme.outline.withValues(alpha: 0.2),
      ),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: value != 'Tout' ? scheme.primary : scheme.onSurface,
        ),
        icon: Icon(
          Icons.expand_more_rounded,
          size: 16,
          color: value != 'Tout'
              ? scheme.primary
              : scheme.onSurface.withValues(alpha: 0.5),
        ),
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e == 'pending'
                      ? 'En attente'
                      : e == 'validated'
                      ? 'Résolu'
                      : e,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    ),
  );
}
