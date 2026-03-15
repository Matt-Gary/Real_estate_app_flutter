import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final stats = await ApiService.getDashboardStats();
      setState(() { _stats = stats; });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendNow() async {
    setState(() => _sending = true);
    try {
      final res = await ApiService.sendNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sent ${res['sent']} message(s)')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
              Text('Dashboard',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _sendNow,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, size: 18),
                label: const Text('Send Now'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_loading) const Center(child: CircularProgressIndicator())
          else if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red))
          else if (_stats != null) _buildStats(),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final s = _stats!;
    final waState = (s['waStatus']?['instance']?['state'] ??
        s['waStatus']?['state'] ?? 'unknown') as String;
    final waColor = waState == 'open' ? Colors.green : Colors.red;

    final statCards = [
      _StatData('Total Clients', s['total'],     const Color(0xFF7F77DD)),
      _StatData('Active',        s['active'],    Colors.green),
      _StatData('Replied',       s['replied'],   Colors.grey),
      _StatData('Msgs Sent',     s['sent'],      const Color(0xFF3B8BD4)),
      _StatData('Pending',       s['pending'],   Colors.orange),
      _StatData('Failed',        s['failed'],    Colors.red),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: statCards.map((d) => _StatCard(data: d)).toList(),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            const Text('WhatsApp: ', style: TextStyle(fontWeight: FontWeight.bold)),
            Icon(Icons.circle, size: 12, color: waColor),
            const SizedBox(width: 6),
            Text(waState, style: TextStyle(color: waColor)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Scheduler: running — fires automatically when messages are due.',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }
}

class _StatData {
  final String label;
  final dynamic value;
  final Color color;
  const _StatData(this.label, this.value, this.color);
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 90,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${data.value}',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: data.color)),
          Text(data.label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
