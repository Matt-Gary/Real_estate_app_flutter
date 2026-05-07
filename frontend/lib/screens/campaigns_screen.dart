import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'campaign_form_screen.dart';
import 'campaign_detail_screen.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  List<dynamic> _campaigns = [];
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
      final data = await ApiService.getCampaigns();
      if (mounted) setState(() { _campaigns = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CampaignFormScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _openDetail(String id) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CampaignDetailScreen(campaignId: id)),
    );
    if (changed == true) _load();
  }

  Future<void> _action(Future<dynamic> Function() fn, String successMsg) async {
    try {
      await fn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg)));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campanhas'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Nova campanha'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _campaigns.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nenhuma campanha ainda.\nUse "Nova campanha" para enviar uma mensagem em massa para clientes com uma etiqueta.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _campaigns.length,
                      itemBuilder: (_, i) => _CampaignCard(
                        campaign: _campaigns[i],
                        onTap: () => _openDetail(_campaigns[i]['id'] as String),
                        onPause: () => _action(
                          () => ApiService.pauseCampaign(_campaigns[i]['id'] as String),
                          'Campanha pausada',
                        ),
                        onResume: () => _action(
                          () => ApiService.resumeCampaign(_campaigns[i]['id'] as String),
                          'Campanha retomada',
                        ),
                        onCancel: () => _confirmCancel(_campaigns[i]),
                        onDelete: () => _confirmDelete(_campaigns[i]),
                      ),
                    ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Campanha excluída')),
        );
      }
      _load();
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
        content: Text('Os envios pendentes de "${campaign['name']}" serão marcados como pulados. Esta ação não pode ser desfeita.'),
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
      _action(() => ApiService.cancelCampaign(campaign['id'] as String), 'Campanha cancelada');
    }
  }
}

class _CampaignCard extends StatelessWidget {
  final dynamic campaign;
  final VoidCallback onTap;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _CampaignCard({
    required this.campaign,
    required this.onTap,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onDelete,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':     return Colors.grey;
      case 'scheduled': return Colors.blue;
      case 'running':   return Colors.green;
      case 'paused':    return Colors.orange;
      case 'completed': return Colors.purple;
      case 'cancelled': return Colors.red;
      default:          return Colors.grey;
    }
  }

  String _statusLabel(String status) => {
    'draft': 'Rascunho',
    'scheduled': 'Agendada',
    'running': 'Em andamento',
    'paused': 'Pausada',
    'completed': 'Concluída',
    'cancelled': 'Cancelada',
  }[status] ?? status;

  @override
  Widget build(BuildContext context) {
    final status = campaign['status'] as String? ?? 'draft';
    final total = (campaign['total_recipients'] as int?) ?? 0;
    final sent = (campaign['sent_count'] as int?) ?? 0;
    final failed = (campaign['failed_count'] as int?) ?? 0;
    final skipped = (campaign['skipped_count'] as int?) ?? 0;
    final progress = total == 0 ? 0.0 : (sent + failed + skipped) / total;
    final color = _statusColor(status);
    final label = campaign['client_labels'];
    final labelName = (label is Map ? label['name'] : null) as String? ?? 'Sem etiqueta';

    String? eta;
    if (status == 'running' && total > 0) {
      final remaining = total - sent - failed - skipped;
      if (remaining > 0) {
        final daily = (campaign['daily_quota'] as int?) ?? 1;
        final days = (remaining / daily).ceil();
        eta = '~$days dia${days == 1 ? '' : 's'} restante${days == 1 ? '' : 's'}';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      campaign['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.label_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(labelName, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 12),
                  if (campaign['start_at'] != null)
                    Text(
                      'Início: ${DateFormat('dd/MM HH:mm').format(DateTime.parse(campaign['start_at']).toLocal())}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                ],
              ),
              if (total > 0) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: progress.clamp(0.0, 1.0), color: color),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('$sent / $total enviadas', style: const TextStyle(fontSize: 12)),
                    if (failed > 0) ...[
                      const SizedBox(width: 12),
                      Text('$failed falhas', style: const TextStyle(fontSize: 12, color: Colors.red)),
                    ],
                    if (skipped > 0) ...[
                      const SizedBox(width: 12),
                      Text('$skipped puladas', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                    const Spacer(),
                    if (eta != null) Text(eta, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (status == 'running') TextButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause, size: 16),
                    label: const Text('Pausar'),
                  ),
                  if (status == 'paused') TextButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Retomar'),
                  ),
                  if (['draft', 'running', 'paused'].contains(status)) TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: const Text('Cancelar', style: TextStyle(color: Colors.red)),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    label: const Text('Excluir', style: TextStyle(color: Colors.red)),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Detalhes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
