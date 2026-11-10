/// Small shared display helpers: status chips, priority badges and the
/// communication status banner.
library;

import 'package:flutter/material.dart';

import '../../models/enums/alert_severity.dart';
import '../../models/enums/flood_severity.dart';
import '../../models/enums/help_category.dart';
import '../../models/enums/shelter_status.dart';
import '../../models/enums/sos_priority.dart';
import '../../models/enums/sos_status.dart';
import '../../models/enums/team_status.dart';
import '../../models/shelter.dart';
import '../../services/ble/ble_service.dart';

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final SosStatus status;

  @override
  Widget build(BuildContext context) {
    return _Chip(
      label: status.label,
      color: _statusColor(status),
    );
  }

  static Color _statusColor(SosStatus status) => switch (status) {
        SosStatus.pending => const Color(0xFFB26A00),
        SosStatus.acknowledged => const Color(0xFF1565C0),
        SosStatus.rescueAssigned => const Color(0xFF6A1B9A),
        SosStatus.inProgress => const Color(0xFF2E7D32),
        SosStatus.resolved => const Color(0xFF455A64),
      };
}

class TeamStatusChip extends StatelessWidget {
  const TeamStatusChip({super.key, required this.status});

  final TeamStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TeamStatus.available => const Color(0xFF2E7D32),
      TeamStatus.responding => const Color(0xFFB26A00),
      TeamStatus.inField => const Color(0xFF1565C0),
      TeamStatus.unavailable => const Color(0xFF455A64),
    };
    return _Chip(label: status.label, color: color);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Shared by the flood report and help-request screens.
class FloodSeverityChip extends StatelessWidget {
  const FloodSeverityChip({super.key, required this.severity});

  final FloodSeverity severity;

  @override
  Widget build(BuildContext context) =>
      _Chip(label: severity.label, color: severityColor(severity));
}

/// Colour for a flood severity. Exposed so cards can tint their border with
/// the same value the chip uses.
Color severityColor(FloodSeverity severity) => switch (severity) {
      FloodSeverity.low => const Color(0xFF2E7D32),
      FloodSeverity.medium => const Color(0xFFB26A00),
      FloodSeverity.high => const Color(0xFFEF6C00),
      FloodSeverity.critical => const Color(0xFFC62828),
    };

/// Water depth chip, tinted darker as the water gets deeper.
class WaterDepthChip extends StatelessWidget {
  const WaterDepthChip({super.key, required this.depth});

  final WaterDepthCategory depth;

  @override
  Widget build(BuildContext context) =>
      _Chip(label: depth.label, color: depthColor(depth));
}

Color depthColor(WaterDepthCategory depth) => switch (depth) {
      WaterDepthCategory.ankleDeep => const Color(0xFF558B2F),
      WaterDepthCategory.kneeDeep => const Color(0xFF9E9D24),
      WaterDepthCategory.waistDeep => const Color(0xFFEF6C00),
      WaterDepthCategory.chestDeep => const Color(0xFFD84315),
      WaterDepthCategory.aboveHead => const Color(0xFF6A1B9A),
    };

class AlertSeverityChip extends StatelessWidget {
  const AlertSeverityChip({super.key, required this.severity});

  final AlertSeverity severity;

  @override
  Widget build(BuildContext context) =>
      _Chip(label: severity.label, color: alertSeverityColor(severity));
}

Color alertSeverityColor(AlertSeverity severity) => switch (severity) {
      AlertSeverity.info => const Color(0xFF1565C0),
      AlertSeverity.warning => const Color(0xFFB26A00),
      AlertSeverity.danger => const Color(0xFFEF6C00),
      AlertSeverity.critical => const Color(0xFFC62828),
    };

/// A shelter's state. Takes the whole [Shelter] rather than a bare status
/// because "closed" is a separate flag from the derived occupancy status — a
/// shelter with free places that is no longer accepting people is the case
/// most likely to mislead someone in a flood.
class ShelterStatusChip extends StatelessWidget {
  const ShelterStatusChip({super.key, required this.shelter});

  final Shelter shelter;

  @override
  Widget build(BuildContext context) {
    if (!shelter.open) {
      return const _Chip(label: 'Closed', color: Color(0xFF455A64));
    }
    return _Chip(
      label: shelter.status.label,
      color: shelterStatusColor(shelter.status),
    );
  }
}

Color shelterStatusColor(ShelterStatus status) => switch (status) {
      ShelterStatus.available => const Color(0xFF2E7D32),
      ShelterStatus.limited => const Color(0xFFB26A00),
      ShelterStatus.full => const Color(0xFFC62828),
    };

/// A help request's status. Distinct from [StatusChip], which is for SOSs.
class HelpStatusChip extends StatelessWidget {
  const HelpStatusChip({super.key, required this.status});

  final HelpRequestStatus status;

  @override
  Widget build(BuildContext context) =>
      _Chip(label: status.label, color: helpStatusColor(status));
}

Color helpStatusColor(HelpRequestStatus status) => switch (status) {
      HelpRequestStatus.pending => const Color(0xFFB26A00),
      HelpRequestStatus.acknowledged => const Color(0xFF1565C0),
      HelpRequestStatus.inProgress => const Color(0xFF2E7D32),
      HelpRequestStatus.fulfilled => const Color(0xFF455A64),
      HelpRequestStatus.cancelled => const Color(0xFF616161),
    };

class HelpCategoryChip extends StatelessWidget {
  const HelpCategoryChip({super.key, required this.category});

  final HelpCategory category;

  @override
  Widget build(BuildContext context) => _Chip(
        label: category.label,
        color: Theme.of(context).colorScheme.primary,
      );
}

// ---------------------------------------------------------------------------
// Priority badge
// ---------------------------------------------------------------------------

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority, this.showLabel = true});

  final SosPriority priority;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (priority) {
      SosPriority.critical => (const Color(0xFFC62828), Icons.warning_amber_rounded),
      SosPriority.high => (const Color(0xFFEF6C00), Icons.arrow_upward),
      SosPriority.medium => (const Color(0xFF1565C0), Icons.remove),
      SosPriority.low => (const Color(0xFF2E7D32), Icons.arrow_downward),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          if (showLabel) ...[
            const SizedBox(width: 4),
            Text(
              priority.label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Communication / link status banner
// ---------------------------------------------------------------------------

class LinkStatusBanner extends StatelessWidget {
  const LinkStatusBanner({super.key, required this.status});

  final CommunicationStatus? status;

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return _banner(context, Icons.link_off, 'Link not started.', Colors.grey);
    }
    return switch (status!.state) {
      CommunicationState.idle => _banner(
          context,
          Icons.link_off,
          'Link idle.',
          Colors.blueGrey,
        ),
      CommunicationState.starting => _banner(
          context,
          Icons.link,
          'Starting peer-to-peer link...',
          Colors.blue,
          busy: true,
        ),
      CommunicationState.relaySearching => _banner(
          context,
          Icons.radar,
          status!.detail,
          Colors.orange,
          busy: true,
        ),
      CommunicationState.attempting => _banner(
          context,
          Icons.wifi_tethering,
          status!.detail,
          Colors.deepPurple,
          busy: true,
        ),
      CommunicationState.ackReceived => _banner(
          context,
          Icons.check_circle,
          'Your SOS has been received by rescue.',
          const Color(0xFF2E7D32),
        ),
      CommunicationState.stopped => _banner(
          context,
          Icons.stop_circle_outlined,
          'Peer-to-peer link stopped.',
          Colors.blueGrey,
        ),
      CommunicationState.error => _banner(
          context,
          Icons.error_outline,
          status!.detail,
          const Color(0xFFC62828),
        ),
    };
  }

  Widget _banner(
    BuildContext context,
    IconData icon,
    String text,
    Color color, {
    bool busy = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
            )
          else
            Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}