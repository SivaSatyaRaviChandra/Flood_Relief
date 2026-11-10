/// "Clear local data" application service.
///
/// Deliberately narrow: it wipes the data the user *produced* (SOS records,
/// relayed packets and the queued-transmission outbox, field reports, help
/// requests, alerts and emergency contacts) and deliberately *keeps* the data
/// the device needs to keep working (rescue teams, shelters, the device
/// identity and every setting). Clearing a device id would orphan the mesh
/// node and force every peer to learn it again, so it is preserved.
library;

import '../core/errors/app_error.dart';
import '../repositories/alert_repository.dart';
import '../repositories/emergency_contact_repository.dart';
import '../repositories/flood_report_repository.dart';
import '../repositories/help_request_repository.dart';
import '../repositories/packet_repository.dart';
import '../repositories/sos_repository.dart';
import '../repositories/shelter_repository.dart';

/// Counts of what a clear removed, so the confirmation can state the result
/// honestly instead of claiming success without evidence.
class ClearedSummary {
  const ClearedSummary({
    this.sosRecords = 0,
    this.packets = 0,
    this.queuedPackets = 0,
    this.floodReports = 0,
    this.helpRequests = 0,
    this.alerts = 0,
    this.contacts = 0,
  });

  final int sosRecords;
  final int packets;
  final int queuedPackets;
  final int floodReports;
  final int helpRequests;
  final int alerts;
  final int contacts;

  int get total =>
      sosRecords +
      packets +
      queuedPackets +
      floodReports +
      helpRequests +
      alerts +
      contacts;

  bool get removedNothing => total == 0;

  /// One sentence, used directly in the success snackbar.
  String describe() {
    if (removedNothing) return 'There was no local data to clear.';
    final parts = <String>[];
    void add(int count, String singular) {
      if (count > 0) parts.add('$count $singular');
    }

    add(sosRecords, 'SOS record${sosRecords == 1 ? '' : 's'}');
    add(packets, 'relayed packet${packets == 1 ? '' : 's'}');
    add(queuedPackets, 'queued packet${queuedPackets == 1 ? '' : 's'}');
    add(floodReports, 'flood report${floodReports == 1 ? '' : 's'}');
    add(helpRequests, 'help request${helpRequests == 1 ? '' : 's'}');
    add(alerts, 'alert${alerts == 1 ? '' : 's'}');
    add(contacts, 'contact${contacts == 1 ? '' : 's'}');
    return 'Cleared ${parts.join(', ')}.';
  }
}

/// Everything currently stored on this device, for the profile / settings
/// screens.
///
/// Separate from [ClearedSummary] because shelters and rescue teams survive a
/// clear — a summary that counted them as "cleared" would be a lie.
class StorageUsage {
  const StorageUsage({
    this.sosRecords = 0,
    this.packets = 0,
    this.queuedPackets = 0,
    this.floodReports = 0,
    this.helpRequests = 0,
    this.shelters = 0,
    this.contacts = 0,
    this.alerts = 0,
  });

  final int sosRecords;
  final int packets;
  final int queuedPackets;
  final int floodReports;
  final int helpRequests;
  final int shelters;
  final int contacts;
  final int alerts;

  bool get isEmpty =>
      sosRecords == 0 &&
      packets == 0 &&
      queuedPackets == 0 &&
      floodReports == 0 &&
      helpRequests == 0 &&
      shelters == 0 &&
      contacts == 0 &&
      alerts == 0;
}

class LocalDataService {
  LocalDataService({
    required SosRepository sosRepository,
    required PacketRepository packetRepository,
    required FloodReportRepository floodReportRepository,
    required HelpRequestRepository helpRequestRepository,
    required AlertRepository alertRepository,
    required EmergencyContactRepository contactRepository,
    required ShelterRepository shelterRepository,
  })  : _sos = sosRepository,
        _packets = packetRepository,
        _reports = floodReportRepository,
        _requests = helpRequestRepository,
        _alerts = alertRepository,
        _contacts = contactRepository,
        _shelters = shelterRepository;

  final SosRepository _sos;
  final PacketRepository _packets;
  final FloodReportRepository _reports;
  final HelpRequestRepository _requests;
  final AlertRepository _alerts;
  final EmergencyContactRepository _contacts;
  final ShelterRepository _shelters;

  /// Removes user-generated local data. Preserved: rescue teams, shelters,
  /// device identity, sign-in state and all settings.
  Future<ClearedSummary> clearUserData() async {
    try {
      // Read the sizes first: the report/alert/contact repositories clear in
      // one shot and do not report how much they removed. Shelters are counted
      // too but deliberately excluded from the summary — a clear keeps them.
      final before = await currentUsage();
      await _sos.clear();
      await _packets.clear();
      await _reports.clear();
      await _requests.clear();
      await _alerts.clear();
      await _contacts.clear();
      return ClearedSummary(
        sosRecords: before.sosRecords,
        packets: before.packets,
        queuedPackets: before.queuedPackets,
        floodReports: before.floodReports,
        helpRequests: before.helpRequests,
        alerts: before.alerts,
        contacts: before.contacts,
      );
    } on AppError {
      rethrow;
    } catch (e) {
      throw DatabaseError(
        'Could not clear local data.',
        cause: e,
      );
    }
  }

  /// Snapshot counts used by Profile and Settings so the screen can show what
  /// is actually on the device before the user commits to deleting it.
  Future<StorageUsage> currentUsage() async {
    final reports = await _reports.getAll();
    final requests = await _requests.getAll();
    final alerts = await _alerts.getAll();
    final contacts = await _contacts.getAll();
    final shelters = await _shelters.getAll();
    final sos = await _sos.getAll();
    final pending = await _packets.pendingPacketIds();
    final packets = await _packets.getPackets();
    return StorageUsage(
      sosRecords: sos.length,
      packets: packets.length,
      queuedPackets: pending.length,
      floodReports: reports.length,
      helpRequests: requests.length,
      shelters: shelters.length,
      contacts: contacts.length,
      alerts: alerts.length,
    );
  }
}
