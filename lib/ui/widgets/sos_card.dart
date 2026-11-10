/// A tappable summary card for one SOS record.
library;

import 'package:flutter/material.dart';

import '../../core/utils/time_format.dart';
import '../../models/sos_request.dart';
import 'badges.dart';

class SosCard extends StatelessWidget {
  const SosCard({super.key, required this.request, this.onTap});

  final SosRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.sosId,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  PriorityBadge(priority: request.priority),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${request.emergencyType.label} — ${request.totalPeople} people',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              if (request.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  request.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  StatusChip(status: request.status),
                  const SizedBox(width: 8),
                  if (request.acknowledged)
                    const Icon(Icons.check_circle,
                        size: 16, color: Color(0xFF2E7D32))
                  else
                    const Icon(Icons.hourglass_empty,
                        size: 16, color: Colors.orange),
                  const Spacer(),
                  Text(
                    formatRelative(request.timestamp),
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12),
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