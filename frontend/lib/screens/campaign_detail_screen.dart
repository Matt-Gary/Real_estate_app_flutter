import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../widgets/batch_plan_table.dart';

/// Live view of a launched campaign — shows current status, progress,
/// and the day-by-day batch plan reflecting actual `campaign_recipients`
/// rows. Lets the agent verify "what's going out and when" any time.
class CampaignDetailScreen extends StatefulWidget {
  final String campaignId;
  const CampaignDetailScreen({super.key, required this.campaignId});

  @override
  State<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends State<CampaignDetailScreen> {
  Map<String, dynamic>? _campaign;
  Map<String, dynamic>? _schedule;
  bool _loading = true;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService.getCampaign(widget.campaignId),
        ApiService.getCampaignSchedule(widget.campaignId),
      ]);
      if (mounted) {
        setState(() {
          _campaign = results[0];
          _schedule = results[1];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted)   {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _runAction(Future<dynamic> Function() fn, String successMsg) async {
    try {
      await fn();
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Color _statusColor(String s) => switch (s) {
        'draft'     => Colors.grey,
        'scheduled' => Colors.blue,
        'running'   => Colors.green,
        'paused'    => Colors.orange,
        'completed' => Colors.purple,
        'cancelled' => Colors.red,
        _           => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {
        if (_changed) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_campaign?['name'] as String? ?? 'Campanha'),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            const SizedBox(width: 8),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final c = _campaign!;
    final s = _schedule!;
    final status = c['status'] as String? ?? 'draft';
    final batchPlan = (s['batchPlan'] as List<dynamic>? ?? []);
    final total = (c['total_recipients'] as int?) ?? 0;
    final sent = (c['sent_count'] as int?) ?? 0;
    final failed = (c['failed_count'] as int?) ?? 0;
    final skipped = (c['skipped_count'] as int?) ?? 0;
    final progress = total == 0 ? 0.0 : (sent + failed + skipped) / total;
    final color = _statusColor(status);
    final label = c['client_labels'];
    final labelName = (label is Map ? label['name'] : null) as String? ?? 'Sem etiqueta';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          {
                            'draft': 'Rascunho',
                            'scheduled': 'Agendada',
                            'running': 'Em andamento',
                            'paused': 'Pausada',
                            'completed': 'Concluída',
                            'cancelled': 'Cancelada',
                          }[status] ?? status,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.label_outline, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(labelName, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (total > 0) ...[
                    LinearProgressIndicator(value: progress.clamp(0.0, 1.0), color: color),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _stat('Total', '$total'),
                      _stat('Enviadas', '$sent', color: Colors.green),
                      if (failed > 0) _stat('Falhas', '$failed', color: Colors.red),
                      if (skipped > 0) _stat('Puladas', '$skipped', color: Colors.grey),
                      _stat('Quota/dia', '${c['daily_quota']}'),
                      if (c['start_at'] != null)
                        _stat('Início', DateFormat('dd/MM HH:mm').format(DateTime.parse(c['start_at']).toLocal())),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (status == 'running')
                        FilledButton.tonalIcon(
                          onPressed: () => _runAction(() => ApiService.pauseCampaign(c['id'] as String), 'Campanha pausada'),
                          icon: const Icon(Icons.pause),
                          label: const Text('Pausar'),
                        ),
                      if (status == 'paused')
                        FilledButton.tonalIcon(
                          onPressed: () => _runAction(() => ApiService.resumeCampaign(c['id'] as String), 'Campanha retomada'),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Retomar'),
                        ),
                      const SizedBox(width: 8),
                      if (['running', 'paused'].contains(status))
                        OutlinedButton.icon(
                          onPressed: () => _confirmCancel(c),
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text('Cancelar', style: TextStyle(color: Colors.red)),
                        ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _confirmDelete(c),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text('Excluir', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Cronograma de envios', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          BatchPlanTable(batchPlan: batchPlan, showProgress: true),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade700, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mensagem',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green.shade900),
                ),
                const SizedBox(height: 8),
                Text(
                  c['template_body'] as String? ?? '',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.green.shade900,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Future<void> _confirmDelete(dynamic campaign) async {
    final status = campaign['status'] as String? ?? 'draft';
    final isActive = status == 'running' || status == 'paused';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir campanha?'),
        content: Text(
          isActive
              ? 'A campanha "${campaign['name']}" está ativa. Vamos cancelar os envios pendentes e excluí-la em seguida. Esta ação não pode ser desfeita.'
              : '"${campaign['name']}" será excluída permanentemente. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      if (isActive) {
        await ApiService.cancelCampaign(campaign['id'] as String);
      }
      await ApiService.deleteCampaign(campaign['id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campanha excluída')),
      );
      Navigator.of(context).pop(true); // signal list to refresh
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _confirmCancel(dynamic campaign) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar campanha?'),
        content: Text('Os envios pendentes de "${campaign['name']}" serão marcados como pulados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar campanha'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _runAction(() => ApiService.cancelCampaign(campaign['id'] as String), 'Campanha cancelada');
    }
  }
}
