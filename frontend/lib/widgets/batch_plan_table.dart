import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Renders the day-by-day campaign send plan as a compact table.
///
/// Accepts the `batchPlan` shape returned by both `/api/campaigns/:id/preview`
/// (pre-launch) and `/api/campaigns/:id/schedule` (post-launch). The schedule
/// variant adds per-day `pendingCount`/`sentCount`/etc. — when present we
/// render a progress bar for that day.
class BatchPlanTable extends StatelessWidget {
  final List<dynamic> batchPlan;
  final bool showProgress;

  const BatchPlanTable({
    super.key,
    required this.batchPlan,
    this.showProgress = false,
  });

  String _fmtDate(String ymd) {
    final parts = ymd.split('-');
    if (parts.length != 3) return ymd;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  String _fmtTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return DateFormat('HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    if (batchPlan.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Nenhum envio planejado.'),
      );
    }

    return Card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 100, child: Text('Data', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 80, child: Text('Envios', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 130, child: Text('Janela', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Amostra', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          ...batchPlan.map((day) => _buildRow(context, day as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext ctx, Map<String, dynamic> day) {
    final preview = (day['recipientPreview'] as List<dynamic>? ?? [])
        .map((p) => p['name'] as String? ?? '?')
        .join(', ');
    final extraTotal = (day['count'] as int? ?? 0) - (day['recipientPreview'] as List<dynamic>? ?? []).length;
    final extraTxt = extraTotal > 0 ? ' +$extraTotal' : '';

    final sent = day['sentCount'] as int?;
    final pending = day['pendingCount'] as int?;
    final failed = day['failedCount'] as int?;
    final skipped = day['skippedCount'] as int?;
    final hasProgress = showProgress && sent != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 100, child: Text(_fmtDate(day['date'] as String))),
              SizedBox(
                width: 80,
                child: Text(
                  '${day['count']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 130,
                child: Text('${_fmtTime(day['firstSendAt'] as String)} – ${_fmtTime(day['lastSendAt'] as String)}'),
              ),
              Expanded(
                child: Text(
                  '$preview$extraTxt',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (hasProgress) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _statBadge(Colors.green, 'Enviadas', sent),
                _statBadge(Colors.orange, 'Pendentes', pending ?? 0),
                if ((failed ?? 0) > 0) _statBadge(Colors.red, 'Falhas', failed!),
                if ((skipped ?? 0) > 0) _statBadge(Colors.grey, 'Puladas', skipped!),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statBadge(Color color, String label, int n) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label $n', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
