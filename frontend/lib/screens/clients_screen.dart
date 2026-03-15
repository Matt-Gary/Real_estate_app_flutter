import 'package:flutter/material.dart';
import 'client_form_screen.dart';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mark as replied'),
        content: Text(
            'Mark ${client["name"]} as replied?\nAll pending follow-ups will be cancelled.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
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
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteClient(dynamic client) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete client'),
        content: Text(
            'Permanently delete ${client["name"]} and all their messages?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
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
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Clients',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Client'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else if (_clients.isEmpty)
            const Center(
              child: Text(
                'No clients yet. Click Add Client to get started.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    return SingleChildScrollView(
      child: Column(
        children: _clients
            .map((c) => _ClientRow(
                  client: c,
                  onEdit: () => _openForm(client: c),
                  onReplied: () => _markReplied(c),
                  onDelete: () => _deleteClient(c),
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

  const _ClientRow({
    required this.client,
    required this.onEdit,
    required this.onReplied,
    required this.onDelete,
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
                    ? Colors.green.withValues (alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isActive ? 'Active' : 'Replied',
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
                tooltip: 'Mark replied',
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
