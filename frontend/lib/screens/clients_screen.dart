import 'package:flutter/material.dart';
import 'client_form_screen.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<dynamic> _clients = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final c = await ApiService.getClients();
      setState(() => _clients = c);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _markReplied(dynamic client) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.markAsReplied),
        content: Text(l10n.markAsRepliedConfirm(client["name"])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.markClientReplied(client['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.error(e.toString()))));
      }
    }
  }

  Future<void> _deleteClient(dynamic client) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.deleteClient),
        content: Text(l10n.deleteClientConfirm(client["name"])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteClient(client['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.error(e.toString()))));
      }
    }
  }

  void _openForm({dynamic client}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClientFormScreen(client: client)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.clients,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.refresh),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.addClient),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else if (_clients.isEmpty)
            Center(
              child: Text(
                l10n.noClients,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          else
            Expanded(child: _buildList(l10n)),
        ],
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    return SingleChildScrollView(
      child: Column(
        children: _clients
            .map((c) => _ClientRow(
                  client: c,
                  onEdit: () => _openForm(client: c),
                  onReplied: () => _markReplied(c),
                  onDelete: () => _deleteClient(c),
                  l10n: l10n,
                ))
            .toList(),
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  final dynamic client;
  final VoidCallback onEdit;
  final VoidCallback onReplied;
  final VoidCallback onDelete;
  final AppLocalizations l10n;

  const _ClientRow({
    required this.client,
    required this.onEdit,
    required this.onReplied,
    required this.onDelete,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = client['is_active'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.circle,
                size: 10, color: isActive ? Colors.green : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(client['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(client['phone_number'],
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isActive ? l10n.statusActive : l10n.statusReplied,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? Colors.green : Colors.grey,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if ((client['total_count'] ?? 0) > 0)
              Text(
                '${client['sent_count']}/${client['total_count']}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
            const SizedBox(width: 12),
            IconButton(
                icon: const Icon(Icons.edit, size: 18), onPressed: onEdit),
            if (isActive)
              IconButton(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                tooltip: l10n.markAsReplied,
                onPressed: onReplied,
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Colors.red),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
