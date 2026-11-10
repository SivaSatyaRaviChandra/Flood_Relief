/// Backend-ready sync boundary.
///
/// The application is offline-first and does NOT require a backend to run.
/// This file defines the contract a FastAPI service can later implement and
/// ships a disabled HTTP client. When enabled via settings the client only
/// *mirrors* already-saved local data; it never blocks the local workflow.
///
/// The expected REST contract (matching `SosRequest.toJson()`):
///
///   POST   /api/v1/sos                       create a SOS
///   GET    /api/v1/sos?status=...            list SOSs for rescue
///   GET    /api/v1/sos/{sos_id}              fetch one SOS
///   PATCH  /api/v1/sos/{sos_id}/status       status transition
///   GET    /api/v1/teams                     list rescue teams
///
/// PostgreSQL-compatible columns are the snake_case fields produced by
/// `SosRequest.toJson()`; see models/sos_request.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/sos_request.dart';

/// Result of a remote sync attempt. Never throws for network problems —
/// offline failures simply produce [RemoteSyncOutcome.skipped].
enum RemoteSyncOutcome { synced, skipped, failed }

class RemoteSyncResult {
  const RemoteSyncResult(this.outcome, this.detail);
  final RemoteSyncOutcome outcome;
  final String detail;
}

abstract class RemoteSyncService {
  bool get enabled;
  Future<void> configure({required bool enabled, required String baseUrl});
  Future<RemoteSyncResult> pushSos(SosRequest request);
  Future<RemoteSyncResult> pushStatusUpdate(String sosId, String status);
}

/// No-op implementation used until a backend is configured. Keeps the system
/// genuinely offline-first.
class DisabledRemoteSyncService implements RemoteSyncService {
  @override
  bool get enabled => false;

  @override
  Future<void> configure({required bool enabled, required String baseUrl}) async {
    // Intentionally a no-op in the no-backend configuration.
  }

  @override
  Future<RemoteSyncResult> pushSos(SosRequest request) async =>
      const RemoteSyncResult(RemoteSyncOutcome.skipped, 'Remote sync disabled.');

  @override
  Future<RemoteSyncResult> pushStatusUpdate(String sosId, String status) async =>
      const RemoteSyncResult(RemoteSyncOutcome.skipped, 'Remote sync disabled.');
}

/// HTTP client for the documented FastAPI contract.
///
/// Accepts self-signed certs for local LAN testing.
class HttpRemoteSyncService implements RemoteSyncService {
  HttpRemoteSyncService({this.baseUrl = ''});

  String baseUrl;
  bool _enabled = false;

  @override
  bool get enabled => _enabled;

  @override
  Future<void> configure({required bool enabled, required String baseUrl}) async {
    _enabled = enabled;
    this.baseUrl = baseUrl;
  }

  static const _timeout = Duration(seconds: 8);

  @override
  Future<RemoteSyncResult> pushSos(SosRequest request) async {
    if (!_enabled || baseUrl.isEmpty) {
      return const RemoteSyncResult(
          RemoteSyncOutcome.skipped, 'Remote sync disabled.');
    }
    try {
      final client = HttpClient()
        ..connectionTimeout = _timeout
        ..badCertificateCallback = ((cert, host, port) => true);
      try {
        final req = await client
            .postUrl(Uri.parse('$baseUrl/api/v1/sos'))
            .timeout(_timeout);
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(request.toJson()));
        final response = await req.close().timeout(_timeout);
        final body = await response.transform(utf8.decoder).join();
        client.close(force: true);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return RemoteSyncResult(
              RemoteSyncOutcome.synced, 'SOS mirrored to backend (${body.length} bytes).');
        }
        return RemoteSyncResult(
            RemoteSyncOutcome.failed, 'Backend replied ${response.statusCode}.');
      } finally {
        client.close();
      }
    } catch (e) {
      return RemoteSyncResult(
          RemoteSyncOutcome.failed, 'Backend unreachable: ${e.runtimeType}.');
    }
  }

  @override
  Future<RemoteSyncResult> pushStatusUpdate(String sosId, String status) async {
    if (!_enabled || baseUrl.isEmpty) {
      return const RemoteSyncResult(
          RemoteSyncOutcome.skipped, 'Remote sync disabled.');
    }
    try {
      final client = HttpClient()..connectionTimeout = _timeout;
      try {
        final req = await client
            .patchUrl(Uri.parse('$baseUrl/api/v1/sos/$sosId/status'))
            .timeout(_timeout);
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'status': status}));
        final response = await req.close().timeout(_timeout);
        await response.transform(utf8.decoder).join();
        client.close(force: true);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return const RemoteSyncResult(
              RemoteSyncOutcome.synced, 'Status mirrored to backend.');
        }
        return RemoteSyncResult(
            RemoteSyncOutcome.failed, 'Backend replied ${response.statusCode}.');
      } finally {
        client.close();
      }
    } catch (e) {
      return RemoteSyncResult(
          RemoteSyncOutcome.failed, 'Backend unreachable: ${e.runtimeType}.');
    }
  }
}

/// Convenience safe value holder used by providers so no async gap exists.
class RemoteSyncSettings {
  const RemoteSyncSettings({this.enabled = false, this.baseUrl = ''});
  final bool enabled;
  final String baseUrl;
}

/// A tiny in-memory event bus so the UI can subscribe to sync results without
/// coupling to HTTP details.
class RemoteSyncEvents {
  final _controller = StreamController<RemoteSyncResult>.broadcast();
  Stream<RemoteSyncResult> get stream => _controller.stream;

  void emit(RemoteSyncResult result) {
    if (_controller.isClosed) return;
    _controller.add(result);
  }

  Future<void> close() => _controller.close();
}