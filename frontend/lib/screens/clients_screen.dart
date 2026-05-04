import 'package:flutter/material.dart';
import 'client_form_screen.dart';
import 'templates_screen.dart';
import '../services/api_service.dart';
import '../widgets/label_chip_input.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen>
    with SingleTickerProviderStateMixin {
  // ── Pendentes state ───────────────────────────────────────────────────────
  List<dynamic> _clients = [];
  bool _loading = true;
  String? _error;
  final Set<String> _selectedIds = {};

  // ── Frios state ───────────────────────────────────────────────────────────
  List<dynamic> _coldClients = [];
  bool _coldLoading = true;
  String? _coldError;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        // Clear selection when switching tabs — stale selections from a
        // different list could otherwise drive accidental bulk actions.
        setState(() => _selectedIds.clear());
      }
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() => Future.wait([_load(), _loadCold()]);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await ApiService.getClients();
      if (!mounted) return;
      setState(() => _clients = c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCold() async {
    setState(() {
      _coldLoading = true;
      _coldError = null;
    });
    try {
      final c = await ApiService.getColdClients();
      if (!mounted) return;
      setState(() => _coldClients = c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _coldError = e.toString());
    } finally {
      if (mounted) setState(() => _coldLoading = false);
    }
  }

  // ── Pendentes actions ─────────────────────────────────────────────────────

  Future<void> _archiveClient(dynamic client) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mover para Não Ativos'),
        content: Text(
          'Mover ${client["name"]} para Clientes Não Ativos?\n\n'
          'Todos os agendamentos pendentes serão cancelados e qualquer '
          'campanha fria será encerrada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.archiveClient(client['id'] as String);
      if (!mounted) return;
      setState(() => _selectedIds.remove(client['id'] as String));
      _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _unarchiveClient(dynamic client) async {
    try {
      await ApiService.unarchiveClient(client['id'] as String);
      if (mounted) _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _archiveColdClient(dynamic cold) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mover para Não Ativos'),
        content: Text(
          'Mover ${cold["client_name"]} para Clientes Não Ativos?\n\n'
          'A campanha fria será encerrada e nenhuma mensagem será enviada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.archiveClient(cold['client_id'] as String);
      if (mounted) _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _markReplied(dynamic client) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Marcar como respondido'),
        content: Text(
          'Marcar ${client["name"]} como respondido?\nTodos os agendamentos pendentes serão cancelados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.markClientReplied(client['id']);
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteClient(dynamic client) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deletar cliente'),
        content: Text(
          'Deletar permanentemente ${client["name"]} e todos os seus agendamentos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteClient(client['id']);
      if (!mounted) return;
      setState(() => _selectedIds.remove(client['id'] as String));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _openForm({dynamic client}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClientFormScreen(client: client)),
    );
    if (mounted) _loadAll();
  }

  // Opens the regular client form for a client living in the Frios tab,
  // so the agent can manage labels/contact info even on cold-campaign clients.
  Future<void> _openClientFromCold(dynamic cold) async {
    try {
      final client = await ApiService.getClient(cold['client_id'] as String);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ClientFormScreen(client: client)),
      );
      if (mounted) _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao abrir cliente: $e')));
      }
    }
  }

  Future<void> _resetClientMessages(dynamic client) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resetar ciclo de mensagens'),
        content: Text(
          'Isto irá apagar todas as mensagens enviadas e agendadas de ${client["name"]}.\n\n'
          'Após confirmar, você poderá configurar um novo ciclo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resetar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.resetClientMessages(client['id'] as String);
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ClientFormScreen(client: client)),
        );
      }
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openColdConfigDialog({
    List<String>? clientIds,
    dynamic coldClient,
    bool directAdd = false,
  }) async {
    // Compute clients not yet in an active cold campaign and not archived
    final coldClientIds = _coldClients
        .map((c) => c['client_id'] as String)
        .toSet();
    final availableClients = _clients
        .where(
          (c) =>
              !coldClientIds.contains(c['id'] as String) &&
              c['archived_at'] == null,
        )
        .toList();

    await showDialog(
      context: context,
      builder: (_) => _ColdConfigDialog(
        clientIds: clientIds,
        coldClient: coldClient,
        availableClients: directAdd ? availableClients : null,
        onSaved: () {
          setState(() => _selectedIds.clear());
          _loadAll();
        },
      ),
    );
  }

  // ── Frios actions ─────────────────────────────────────────────────────────

  Future<void> _toggleColdActive(dynamic cold) async {
    try {
      await ApiService.updateColdClient(cold['id'] as String, {
        'is_active': !(cold['is_active'] as bool),
      });
      if (mounted) _loadCold();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _moveColdToPendentes(dynamic cold) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mover para Clientes Pendentes'),
        content: Text(
          'Mover ${cold["client_name"]} de volta para Clientes Pendentes?\n\n'
          'A campanha fria será encerrada e você poderá configurar '
          'um novo ciclo de mensagens de follow-up.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteColdClient(cold['id'] as String);
      if (!mounted) return;
      final client = await ApiService.getClient(cold['client_id'] as String);
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ClientFormScreen(client: client)),
        );
      }
      if (mounted) _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _deleteColdClient(dynamic cold) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deletar cliente'),
        content: Text(
          'Deletar permanentemente ${cold["client_name"]} e todos os seus dados?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteClient(cold['client_id'] as String);
      if (mounted) _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Clientes Pendentes'),
              Tab(text: 'Clientes Frios'),
              Tab(text: 'Clientes Não Ativos'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPendentesTab(),
                _buildFriosTab(),
                _buildNaoAtivosTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final hasSelection = _selectedIds.isNotEmpty;
    final tabIndex = _tabController.index;
    final onPendentesTab = tabIndex == 0;
    final onFriosTab = tabIndex == 1;
    return Row(
      children: [
        Text(
          'Clientes',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        if (hasSelection && onPendentesTab) ...[
          Text(
            '${_selectedIds.length} selecionado(s)',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () =>
                _openColdConfigDialog(clientIds: _selectedIds.toList()),
            icon: const Icon(Icons.ac_unit, size: 18),
            label: const Text('Enviar para Clientes Frios'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            child: const Text('Cancelar'),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Atualizar'),
          ),
          const SizedBox(width: 8),
          if (onFriosTab)
            FilledButton.icon(
              onPressed: () => _openColdConfigDialog(directAdd: true),
              icon: const Icon(Icons.ac_unit, size: 18),
              label: const Text('Adicionar para Frios'),
            )
          else if (onPendentesTab)
            FilledButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar Cliente'),
            ),
        ],
      ],
    );
  }

  // ── Pendentes tab ─────────────────────────────────────────────────────────

  Widget _buildPendentesTab() {
    if (_loading || _coldLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: Colors.red));
    }

    // Hide clients already in an active cold campaign or archived
    final coldClientIds = _coldClients
        .map((c) => c['client_id'] as String)
        .toSet();
    final pendentes = _clients
        .where(
          (c) =>
              !coldClientIds.contains(c['id'] as String) &&
              c['archived_at'] == null,
        )
        .toList();

    if (pendentes.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum cliente pendente. Adicione um novo cliente para começar.',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: pendentes
            .map(
              (c) => _ClientRow(
                client: c,
                selected: _selectedIds.contains(c['id'] as String),
                onSelect: (v) => setState(() {
                  if (v) {
                    _selectedIds.add(c['id'] as String);
                  } else {
                    _selectedIds.remove(c['id'] as String);
                  }
                }),
                onEdit: () => _openForm(client: c),
                onReplied: () => _markReplied(c),
                onDelete: () => _deleteClient(c),
                onReset: () => _resetClientMessages(c),
                onArchive: () => _archiveClient(c),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Não Ativos tab ────────────────────────────────────────────────────────

  Widget _buildNaoAtivosTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: Colors.red));
    }

    final naoAtivos = _clients.where((c) => c['archived_at'] != null).toList()
      ..sort((a, b) {
        final aDt =
            DateTime.tryParse(a['archived_at'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDt =
            DateTime.tryParse(b['archived_at'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aDt.compareTo(bDt);
      });

    if (naoAtivos.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum cliente não ativo. Arquive clientes a partir de Pendentes ou Frios.',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: naoAtivos
            .map(
              (c) => _ClientRow(
                client: c,
                selected: false,
                showCheckbox: false,
                onSelect: (_) {},
                onEdit: () => _openForm(client: c),
                onDelete: () => _deleteClient(c),
                onUnarchive: () => _unarchiveClient(c),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Frios tab ─────────────────────────────────────────────────────────────

  Widget _buildFriosTab() {
    if (_coldLoading) return const Center(child: CircularProgressIndicator());
    if (_coldError != null) {
      return Text(_coldError!, style: const TextStyle(color: Colors.red));
    }
    if (_coldClients.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum cliente frio. Selecione clientes na aba Pendentes e clique em "Enviar para Clientes Frios".',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: _coldClients
            .map(
              (c) => _ColdClientRow(
                cold: c,
                onToggle: () => _toggleColdActive(c),
                onEdit: () => _openColdConfigDialog(coldClient: c),
                onEditClient: () => _openClientFromCold(c),
                onDelete: () => _deleteColdClient(c),
                onMoveToPendentes: () => _moveColdToPendentes(c),
                onArchive: () => _archiveColdClient(c),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── _ClientRow ────────────────────────────────────────────────────────────────

class _ClientRow extends StatelessWidget {
  final dynamic client;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final VoidCallback onEdit;
  final VoidCallback? onReplied;
  final VoidCallback onDelete;
  final VoidCallback? onReset;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final bool showCheckbox;

  const _ClientRow({
    required this.client,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    this.onReplied,
    this.onReset,
    this.onArchive,
    this.onUnarchive,
    this.showCheckbox = true,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = client['is_active'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (showCheckbox) ...[
              Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
              const SizedBox(width: 4),
            ],
            Icon(
              Icons.circle,
              size: 10,
              color: isActive ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    client['phone_number'],
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  if ((client['labels'] as List<dynamic>? ?? [])
                      .isNotEmpty) ...[
                    const SizedBox(height: 4),
                    LabelChipsDisplay(
                      labels: client['labels'] as List<dynamic>,
                    ),
                  ],
                ],
              ),
            ),
            Builder(
              builder: (_) {
                final optedOut = client['opted_out_at'] != null;
                final archived = client['archived_at'] != null;
                // For archived clients (without opt-out), the brown
                // "Arquivado em ..." chip below replaces the status badge.
                if (archived && !optedOut) return const SizedBox.shrink();
                final Color color;
                final String label;
                if (optedOut) {
                  color = Colors.red;
                  label = 'Opt-out';
                } else if (isActive) {
                  color = Colors.green;
                  label = 'Ativo';
                } else {
                  color = Colors.grey;
                  label = 'Respondido';
                }
                final chip = Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                );
                if (optedOut) {
                  final reason = client['opt_out_reason'] as String?;
                  return Tooltip(
                    message: reason != null && reason.isNotEmpty
                        ? 'Cliente pediu para parar: "$reason"'
                        : 'Cliente pediu para parar',
                    child: chip,
                  );
                }
                return chip;
              },
            ),
            if (client['archived_at'] != null) ...[
              const SizedBox(width: 6),
              Builder(
                builder: (_) {
                  final dt = DateTime.tryParse(
                    client['archived_at'] as String,
                  )?.toLocal();
                  final label = dt == null
                      ? 'Arquivado'
                      : 'Arquivado em ${dt.day.toString().padLeft(2, '0')}/'
                            '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.brown.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 12, color: Colors.brown),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(width: 8),
            if ((client['total_count'] ?? 0) > 0 &&
                client['archived_at'] == null) ...[
              Text(
                '${client['sent_count']}/${client['total_count']}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
              if (onReset != null)
                IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  tooltip: 'Resetar ciclo',
                  color: Colors.orange,
                  onPressed: onReset,
                ),
            ] else
              const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: onEdit,
            ),
            if (isActive && onReplied != null)
              IconButton(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                tooltip: 'Marcar como respondido',
                onPressed: onReplied,
              ),
            if (onArchive != null)
              IconButton(
                icon: const Icon(
                  Icons.archive_outlined,
                  size: 18,
                  color: Colors.brown,
                ),
                tooltip: 'Mover para Não Ativos',
                onPressed: onArchive,
              ),
            if (onUnarchive != null)
              IconButton(
                icon: const Icon(
                  Icons.unarchive_outlined,
                  size: 18,
                  color: Colors.green,
                ),
                tooltip: 'Reativar (mover para Pendentes)',
                onPressed: onUnarchive,
              ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red,
              ),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ── _ColdClientRow ────────────────────────────────────────────────────────────

class _ColdClientRow extends StatelessWidget {
  final dynamic cold;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onEditClient;
  final VoidCallback onDelete;
  final VoidCallback onMoveToPendentes;
  final VoidCallback onArchive;

  const _ColdClientRow({
    required this.cold,
    required this.onToggle,
    required this.onEdit,
    required this.onEditClient,
    required this.onDelete,
    required this.onMoveToPendentes,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = cold['is_active'] == true;
    final int sent = cold['messages_sent'] ?? 0;
    final int? max = cold['max_messages'] as int?;
    final String counter = max != null ? '$sent/$max' : '$sent';
    final int interval = cold['interval_days'] ?? 14;
    final String? templateName = cold['template_name'] as String?;

    String? nextSendLabel;
    if (isActive && cold['next_send_at'] != null) {
      final dt = DateTime.tryParse(cold['next_send_at'] as String);
      if (dt != null) {
        final local = dt.toLocal();
        nextSendLabel =
            '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.ac_unit,
              size: 16,
              color: isActive ? Colors.blueAccent : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cold['client_name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    cold['phone_number'] ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip(
                        Icons.schedule,
                        'A cada $interval dias',
                        Colors.blueGrey,
                      ),
                      _chip(Icons.send, '$counter enviadas', Colors.blueAccent),
                      if (templateName != null)
                        _chip(Icons.description, templateName, Colors.teal),
                      if (nextSendLabel != null)
                        _chip(
                          Icons.alarm,
                          'Próximo: $nextSendLabel',
                          Colors.orange,
                        ),
                    ],
                  ),
                  if ((cold['labels'] as List<dynamic>? ?? []).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    LabelChipsDisplay(labels: cold['labels'] as List<dynamic>),
                  ],
                ],
              ),
            ),
            Switch(value: isActive, onChanged: (_) => onToggle()),
            IconButton(
              icon: const Icon(Icons.undo, size: 18),
              tooltip: 'Mover para Clientes Pendentes',
              color: Colors.green,
              onPressed: onMoveToPendentes,
            ),
            IconButton(
              icon: const Icon(
                Icons.archive_outlined,
                size: 18,
                color: Colors.brown,
              ),
              tooltip: 'Mover para Não Ativos',
              onPressed: onArchive,
            ),
            IconButton(
              icon: const Icon(Icons.person_outline, size: 18),
              tooltip: 'Editar cliente (etiquetas, contato)',
              onPressed: onEditClient,
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              tooltip: 'Editar campanha fria',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red,
              ),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

// ── _ColdConfigDialog ─────────────────────────────────────────────────────────

class _ColdConfigDialog extends StatefulWidget {
  /// For creating via multi-select from Pendentes: list of pre-selected client_ids
  final List<String>? clientIds;

  /// For editing: existing cold_client record
  final dynamic coldClient;

  /// For adding directly from Frios tab: list of eligible clients to pick from
  final List<dynamic>? availableClients;

  final VoidCallback onSaved;

  const _ColdConfigDialog({
    this.clientIds,
    this.coldClient,
    this.availableClients,
    required this.onSaved,
  });

  @override
  State<_ColdConfigDialog> createState() => _ColdConfigDialogState();
}

class _ColdConfigDialogState extends State<_ColdConfigDialog> {
  List<dynamic> _templates = [];
  String? _selectedTemplateId;
  final _intervalCtrl = TextEditingController(text: '14');
  final _maxCtrl = TextEditingController();
  DateTime? _firstSendAt;
  String? _selectedClientId; // used only in directAdd mode
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    if (widget.coldClient != null) {
      _selectedTemplateId = widget.coldClient['template_id'] as String?;
      _intervalCtrl.text = (widget.coldClient['interval_days'] as int? ?? 14)
          .toString();
      final max = widget.coldClient['max_messages'];
      if (max != null) _maxCtrl.text = max.toString();
      final nextRaw = widget.coldClient['next_send_at'] as String?;
      if (nextRaw != null) {
        _firstSendAt = DateTime.tryParse(nextRaw)?.toLocal();
      }
    }
  }

  @override
  void dispose() {
    _intervalCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final t = await ApiService.getTemplates();
      if (!mounted) return;
      setState(() {
        _templates = t;
        // If the pre-selected template no longer exists in the list, clear it
        if (_selectedTemplateId != null &&
            !t.any((tpl) => tpl['id'] == _selectedTemplateId)) {
          _selectedTemplateId = null;
        }
      });
    } catch (_) {}
  }

  Future<void> _openAddTemplate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TemplatesScreen()),
    );
    await _loadTemplates();
  }

  Future<void> _pickSendAt() async {
    final now = DateTime.now();
    final initial = _firstSendAt ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? initial : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (picked.isBefore(DateTime.now())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O horário selecionado já passou. Escolha um horário futuro.',
          ),
        ),
      );
      return;
    }

    setState(() => _firstSendAt = picked);
  }

  Future<void> _save() async {
    if (_saving) return;

    final bool isDirectAdd = widget.availableClients != null;
    if (isDirectAdd && _selectedClientId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecione um cliente.')));
      return;
    }
    if (_selectedTemplateId == null ||
        !_templates.any((t) => t['id'] == _selectedTemplateId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um template de mensagem antes de salvar.'),
        ),
      );
      return;
    }
    if (_firstSendAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Defina a data e hora do primeiro envio.'),
        ),
      );
      return;
    }

    final int? intervalDays = int.tryParse(_intervalCtrl.text.trim());
    if (intervalDays == null || intervalDays < 1 || intervalDays > 365) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O intervalo deve ser um número entre 1 e 365 dias.'),
        ),
      );
      return;
    }

    final int? maxMessages = _maxCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_maxCtrl.text.trim());
    final String firstSendAtUtc = _firstSendAt!.toUtc().toIso8601String();

    setState(() => _saving = true);
    try {
      if (widget.coldClient != null) {
        // Edit existing
        await ApiService.updateColdClient(widget.coldClient['id'] as String, {
          'template_id': _selectedTemplateId,
          'interval_days': intervalDays,
          'max_messages': maxMessages,
          'next_send_at': firstSendAtUtc,
        });
      } else {
        // Create — either from directAdd (single client) or multi-select
        final ids = isDirectAdd
            ? [_selectedClientId!]
            : (widget.clientIds ?? []);
        for (final clientId in ids) {
          try {
            await ApiService.createColdClient({
              'client_id': clientId,
              'template_id': _selectedTemplateId,
              'interval_days': intervalDays,
              'max_messages': maxMessages,
              'first_send_at': firstSendAtUtc,
            });
          } catch (e) {
            if (e.toString().contains('already in an active cold campaign')) {
              continue;
            }
            rethrow;
          }
        }
      }
      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.coldClient != null;
    final isDirectAdd = widget.availableClients != null;
    final count = widget.clientIds?.length ?? 1;

    return AlertDialog(
      title: Text(
        isEdit
            ? 'Editar campanha fria'
            : isDirectAdd
            ? 'Adicionar cliente frio'
            : 'Enviar $count cliente${count > 1 ? 's' : ''} para Clientes Frios',
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Client picker (directAdd mode only)
              if (isDirectAdd) ...[
                const Text(
                  'Cliente',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButton<String>(
                    value: _selectedClientId,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    hint: const Text('Selecionar cliente *'),
                    items: (widget.availableClients ?? [])
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c['id'] as String,
                            child: Text(
                              '${c['name']}  •  ${c['phone_number']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedClientId = v),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Template
              const Text(
                'Template de mensagem *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButton<String>(
                  // Guard: if templates haven't loaded yet the value won't
                  // be in the items list, causing an assertion crash.
                  value: _templates.any((t) => t['id'] == _selectedTemplateId)
                      ? _selectedTemplateId
                      : null,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  hint: const Text('Selecionar template *'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('— nenhum —'),
                    ),
                    ..._templates.map(
                      (t) => DropdownMenuItem<String>(
                        value: t['id'] as String,
                        child: Text(t['name'] as String),
                      ),
                    ),
                    const DropdownMenuItem<String>(
                      value: '__ADD_TEMPLATE__',
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 16, color: Colors.blue),
                          SizedBox(width: 6),
                          Text(
                            'Adicionar template',
                            style: TextStyle(color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (v) async {
                    if (v == '__ADD_TEMPLATE__') {
                      await _openAddTemplate();
                      return;
                    }
                    setState(() => _selectedTemplateId = v);
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Interval
              const Text(
                'Intervalo de envio (dias)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _intervalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'Ex: 14',
                  suffixText: 'dias (1–365)',
                ),
              ),
              const SizedBox(height: 16),

              // First / next send date+time
              Text(
                widget.coldClient != null ? 'Próximo envio' : 'Primeiro envio',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _pickSendAt,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  _firstSendAt != null
                      ? '${_firstSendAt!.day.toString().padLeft(2, '0')}/${_firstSendAt!.month.toString().padLeft(2, '0')}/${_firstSendAt!.year}  ${_firstSendAt!.hour.toString().padLeft(2, '0')}:${_firstSendAt!.minute.toString().padLeft(2, '0')}'
                      : 'Selecionar data e hora *',
                  style: TextStyle(
                    color: _firstSendAt != null ? null : Colors.red.shade400,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Max messages
              const Text(
                'Máximo de mensagens (opcional)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _maxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'Deixe em branco para ilimitado',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Salvar' : 'Confirmar'),
        ),
      ],
    );
  }
}
