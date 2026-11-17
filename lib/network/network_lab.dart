import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../data/lab_repository.dart';
import '../platform/distance_probe.dart';
import '../platform/ble_beacon.dart';
import 'tcp_transfer.dart';
import 'udp_echo.dart';

class DiscoveredServer {
  const DiscoveredServer(this.address, this.port);
  final InternetAddress address;
  final int port;
  Uri get uri => Uri(scheme: 'http', host: address.address, port: port);
}

class _CoordinatedJob {
  _CoordinatedJob({
    required this.id,
    required this.session,
    required this.phase,
    required this.testId,
    required this.trialId,
    required this.config,
    required this.clients,
    required this.serverDistances,
  }) : startUtc = DateTime.now().toUtc().add(const Duration(seconds: 2));
  final String id;
  final LabSession session;
  final LabPhase phase;
  final String testId;
  final String trialId;
  final TrialConfig config;
  final Set<String> clients;
  final Map<String, DistanceObservation> serverDistances;
  final DateTime startUtc;
  final Set<String> delivered = {};
  final Set<String> completed = {};
  final Completer<void> done = Completer<void>();
  bool reconciled = false;
}

class NetworkLab {
  NetworkLab(this.repository, {this.distanceProbe = const DistanceProbe()})
    : clientId = repository.clientIdentity;
  final LabRepository repository;
  final DistanceProbe distanceProbe;
  static const protocolVersion = 1;
  static const maxDownloadBytes = 100 * 1024 * 1024;
  static const mdnsServiceType = '_lanxis._tcp';
  static const _uuid = Uuid();
  static const _participantService = MethodChannel('mx.lanxis/participant');
  HttpServer? _server;
  TcpTransferServer? _tcpTransfer;
  UdpEchoServer? _udpEcho;
  RawDatagramSocket? _discoverySocket;
  BonsoirBroadcast? _mdnsBroadcast;
  Future<void>? _mdnsStartTask;
  BleBeacon? _bleBeacon;
  BleBeacon? _participantBeacon;
  final Map<String, String> _clientBeaconTokens = {};
  String? participantBeaconError;
  String? bleBeaconError;
  String? mdnsError;
  bool get mdnsActive => _mdnsBroadcast != null;
  bool get bleBeaconActive => _bleBeacon != null;
  StreamSubscription<RawSocketEvent>? _discoverySubscription;
  int _activeTransfers = 0;
  String? _pairCode;
  final String clientId;
  final Map<String, DateTime> _clients = {};
  final Map<String, DateTime> _readyWorkers = {};
  _CoordinatedJob? _activeJob;
  final Map<String, _CoordinatedJob> _recentJobs = {};
  bool _participating = false;
  Future<void>? _participantTask;
  String? lastParticipantError;
  String? lastDistanceReason;
  UdpBurstResult? lastUdpBurstResult;

  bool get isServing => _server != null;
  int? get port => _server?.port;
  String? get pairCode => _pairCode;
  int get connectedClients => _clients.length;
  int get readyWorkers => _readyWorkers.entries
      .where((e) => DateTime.now().toUtc().difference(e.value).inSeconds < 8)
      .length;
  int get deliveredWorkers => _activeJob?.delivered.length ?? 0;
  int get completedWorkers => _activeJob?.completed.length ?? 0;
  int get coordinatedSamples => _activeJob == null
      ? 0
      : repository.trialMeasurementCount(_activeJob!.trialId);
  bool get isParticipating => _participating;

  Future<int> startServer({int port = 8040}) async {
    if (_server != null) return _server!.port;
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: false,
    );
    _pairCode = (100000 + Random.secure().nextInt(900000)).toString();
    _server = server;
    try {
      final transfer = TcpTransferServer(_pairCode!, maxDownloadBytes);
      await transfer.start();
      _tcpTransfer = transfer;
    } on SocketException {
      // HTTP remains usable if this device cannot open a second port.
    }
    try {
      final echo = UdpEchoServer(_pairCode!);
      await echo.start();
      _udpEcho = echo;
    } on SocketException {
      // Datagram echo is optional when the platform denies UDP binding.
    }
    try {
      final discovery = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        8041,
      );
      discovery.broadcastEnabled = true;
      _discoverySocket = discovery;
      _discoverySubscription = discovery.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = discovery.receive()) != null) {
          if (utf8.decode(packet!.data, allowMalformed: true).trim() !=
              'LANXIS_DISCOVER_V1') {
            continue;
          }
          discovery.send(
            utf8.encode(
              jsonEncode({
                'name': 'LANXIS',
                'version': protocolVersion,
                'port': server.port,
              }),
            ),
            packet.address,
            packet.port,
          );
        }
      });
    } on SocketException {
      // Manual IP connection remains available when UDP is blocked or occupied.
    }
    if ((Platform.isLinux || Platform.isAndroid) && server.port == 8040) {
      try {
        _bleBeacon = await BleBeacon.start();
        bleBeaconError = null;
      } catch (error) {
        bleBeaconError = '$error';
      }
    }
    unawaited(server.forEach(_handleRequest));
    _mdnsStartTask = _startMdns(server);
    return server.port;
  }

  Future<void> _startMdns(HttpServer server) async {
    BonsoirBroadcast? mdns;
    try {
      mdns = BonsoirBroadcast(
        printLogs: false,
        service: BonsoirService(
          name: 'LANXIS-${clientId.substring(0, 8)}',
          type: mdnsServiceType,
          port: server.port,
          attributes: {'proto': '$protocolVersion'},
        ),
      );
      await mdns.initialize().timeout(const Duration(seconds: 3));
      await mdns.start().timeout(const Duration(seconds: 3));
      if (!identical(_server, server)) {
        await mdns.stop().timeout(const Duration(seconds: 2));
        return;
      }
      _mdnsBroadcast = mdns;
      mdnsError = null;
    } catch (error) {
      mdnsError = '$error';
      try {
        await mdns?.stop().timeout(const Duration(seconds: 1));
      } catch (_) {
        // Other discovery methods still work without mDNS.
      }
    }
  }

  Future<void> stopServer() async {
    await _mdnsStartTask;
    _mdnsStartTask = null;
    try {
      await _mdnsBroadcast?.stop().timeout(const Duration(seconds: 2));
    } catch (_) {
      // The native mDNS service may already have stopped.
    }
    _mdnsBroadcast = null;
    await _bleBeacon?.close();
    _bleBeacon = null;
    await _udpEcho?.close();
    _udpEcho = null;
    await _tcpTransfer?.close();
    _tcpTransfer = null;
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    await _server?.close(force: true);
    _server = null;
    _pairCode = null;
    _clients.clear();
    _readyWorkers.clear();
    _clientBeaconTokens.clear();
    _recentJobs.clear();
  }

  Future<List<DiscoveredServer>> discover({
    Duration duration = const Duration(seconds: 2),
    InternetAddress? target,
    Iterable<InternetAddress>? fallbackAddresses,
    int fallbackPort = 8040,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final found = <String, DiscoveredServer>{};
    final mdnsTask = target == null
        ? _discoverMdns(found, duration)
        : Future<void>.value();
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = socket.receive()) != null) {
        try {
          final data = jsonDecode(utf8.decode(packet!.data));
          if (data is! Map ||
              data['name'] != 'LANXIS' ||
              data['version'] != protocolVersion ||
              data['port'] is! int) {
            continue;
          }
          final server = DiscoveredServer(packet.address, data['port'] as int);
          found[server.address.address] = server;
        } on FormatException {
          // Other UDP broadcasts on the LAN are unrelated to LANXIS.
        }
      }
    });
    try {
      var localInterfaces = <NetworkInterface>[];
      final destinations = <String>{
        if (target != null) target.address else '255.255.255.255',
      };
      if (target == null) {
        // Some routers drop the all-subnets broadcast but accept a subnet one.
        localInterfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        for (final interface in localInterfaces) {
          for (final ip in interface.addresses) {
            if (ip.isLoopback || ip.rawAddress.length != 4) continue;
            final octets = ip.rawAddress;
            destinations.add('${octets[0]}.${octets[1]}.${octets[2]}.255');
          }
        }
      }
      for (final destination in destinations) {
        try {
          socket.send(
            utf8.encode('LANXIS_DISCOVER_V1'),
            InternetAddress(destination),
            8041,
          );
        } on SocketException {
          // Keep trying the remaining interfaces.
        }
      }
      await Future<void>.delayed(duration);
      await mdnsTask;
      if (found.isEmpty && (target == null || fallbackAddresses != null)) {
        final candidates =
            fallbackAddresses ?? _localScanAddresses(localInterfaces);
        for (final server in await _scanHealth(candidates, fallbackPort)) {
          found[server.address.address] = server;
        }
      }
      return found.values.toList();
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  Future<void> _discoverMdns(
    Map<String, DiscoveredServer> found,
    Duration duration,
  ) async {
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? events;
    try {
      discovery = BonsoirDiscovery(type: mdnsServiceType, printLogs: false);
      await discovery.initialize().timeout(const Duration(seconds: 3));
      events = discovery.eventStream?.listen((event) {
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          unawaited(
            event.service
                .resolve(discovery!.serviceResolver)
                .catchError((Object _) {}),
          );
        } else if (event is BonsoirDiscoveryServiceResolvedEvent ||
            event is BonsoirDiscoveryServiceUpdatedEvent) {
          final service = event.service;
          if (service == null ||
              service.attributes['proto'] != '$protocolVersion' ||
              service.port < 1 ||
              service.port > 65535) {
            return;
          }
          for (final host in service.hostAddresses) {
            final address = InternetAddress.tryParse(host);
            if (address == null ||
                address.type != InternetAddressType.IPv4 ||
                address.isLoopback) {
              continue;
            }
            found[address.address] = DiscoveredServer(address, service.port);
          }
        }
      });
      await discovery.start().timeout(const Duration(seconds: 3));
      await Future<void>.delayed(duration);
    } catch (_) {
      // UDP discovery, health scan and manual URL remain available.
    } finally {
      await events?.cancel();
      try {
        await discovery?.stop().timeout(const Duration(seconds: 2));
      } catch (_) {
        // Native discovery may have stopped before cancellation.
      }
    }
  }

  Iterable<InternetAddress> _localScanAddresses(
    List<NetworkInterface> interfaces,
  ) sync* {
    final preferred = interfaces.where(
      (item) => RegExp(
        r'^(wlan|wifi|wi-fi|wl|eth|en|ap)',
        caseSensitive: false,
      ).hasMatch(item.name),
    );
    final selected = preferred.isEmpty ? interfaces : preferred;
    final seen = <String>{};
    for (final interface in selected.take(2)) {
      for (final address in interface.addresses) {
        final bytes = address.rawAddress;
        if (bytes.length != 4 ||
            !(bytes[0] == 10 ||
                bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31 ||
                bytes[0] == 192 && bytes[1] == 168)) {
          continue;
        }
        for (var last = 1; last < 255; last++) {
          if (last == bytes[3]) continue;
          final host = '${bytes[0]}.${bytes[1]}.${bytes[2]}.$last';
          if (seen.add(host)) yield InternetAddress(host);
        }
      }
    }
  }

  Future<List<DiscoveredServer>> _scanHealth(
    Iterable<InternetAddress> addresses,
    int port,
  ) async {
    final candidates = addresses.take(508).toList();
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 350);
    Future<DiscoveredServer?> check(InternetAddress address) async {
      try {
        final uri = Uri(
          scheme: 'http',
          host: address.address,
          port: port,
          path: '/health',
        );
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(milliseconds: 500));
        final response = await request.close().timeout(
          const Duration(milliseconds: 500),
        );
        if (response.statusCode != HttpStatus.ok) return null;
        final data = jsonDecode(
          await utf8.decoder
              .bind(response)
              .join()
              .timeout(const Duration(milliseconds: 500)),
        );
        if (data is Map &&
            data['name'] == 'LANXIS' &&
            data['version'] == protocolVersion) {
          return DiscoveredServer(address, port);
        }
      } catch (_) {
        // A closed port or another service is expected during LAN discovery.
      }
      return null;
    }

    try {
      final found = <DiscoveredServer>[];
      for (var index = 0; index < candidates.length; index += 32) {
        final batch = await Future.wait(
          candidates.skip(index).take(32).map(check),
        );
        found.addAll(batch.whereType<DiscoveredServer>());
      }
      return found;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.set('X-Lanxis-Protocol', '$protocolVersion');
    response.headers.contentType = ContentType.json;
    try {
      if (request.method != 'GET' && request.method != 'POST') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.write(jsonEncode({'error': 'method_not_allowed'}));
      } else if (request.uri.path == '/health') {
        response.write(
          jsonEncode({
            'name': 'LANXIS',
            'version': protocolVersion,
            if (_tcpTransfer?.port != null) 'tcp_port': _tcpTransfer!.port,
            if (_udpEcho?.port != null) 'udp_port': _udpEcho!.port,
            'capabilities': [
              'http-ping',
              'http-download',
              'http-upload',
              'http-register',
              'coordinated-trial',
              if (_tcpTransfer != null) 'tcp-transfer',
              if (_udpEcho != null) 'udp-echo',
              if (_discoverySocket != null) 'udp-discovery',
              if (_mdnsBroadcast != null) 'mdns-discovery',
              if (_bleBeacon != null) 'ble-distance-estimate',
            ],
            if (_bleBeacon != null) 'distance_beacon_token': _bleBeacon!.token,
          }),
        );
      } else if (request.headers.value('X-Lanxis-Code') != _pairCode) {
        response.statusCode = HttpStatus.unauthorized;
        response.write(jsonEncode({'error': 'pairing_required'}));
      } else if (request.uri.path == '/register' && request.method == 'POST') {
        if (request.contentLength > 4096) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          response.write(jsonEncode({'error': 'registration_too_large'}));
        } else {
          final body = await utf8.decoder.bind(request).join();
          Object? data;
          try {
            data = jsonDecode(body);
          } on FormatException {
            data = null;
          }
          final id = data is Map ? data['client_id'] : null;
          final beaconToken = data is Map
              ? data['distance_beacon_token']
              : null;
          if (id is! String || id.length < 8 || id.length > 128) {
            response.statusCode = HttpStatus.badRequest;
            response.write(jsonEncode({'error': 'invalid_client_id'}));
          } else {
            _clients[id] = DateTime.now().toUtc();
            if (beaconToken is String &&
                RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(beaconToken)) {
              _clientBeaconTokens[id] = beaconToken;
            } else {
              _clientBeaconTokens.remove(id);
            }
            response.write(
              jsonEncode({
                'client_id': id,
                'registered_utc': _clients[id]!.toIso8601String(),
                'clients': _clients.length,
              }),
            );
          }
        }
      } else if (request.uri.path == '/work' && request.method == 'GET') {
        final id = request.uri.queryParameters['client_id'];
        if (id == null || !_clients.containsKey(id)) {
          response.statusCode = HttpStatus.forbidden;
          response.write(jsonEncode({'error': 'client_not_registered'}));
        } else {
          _readyWorkers[id] = DateTime.now().toUtc();
          final job = _activeJob;
          if (job == null ||
              !job.clients.contains(id) ||
              !job.delivered.add(id)) {
            response.write(jsonEncode({'job': null}));
          } else {
            response.write(
              jsonEncode({
                'job': {
                  'id': job.id,
                  'session_name': job.session.name,
                  'phase_name': job.phase.name,
                  'start_utc': job.startUtc.toIso8601String(),
                  'server_utc': DateTime.now().toUtc().toIso8601String(),
                  'config': job.config.toJson(),
                },
              }),
            );
          }
        }
      } else if (request.uri.path == '/result' && request.method == 'POST') {
        if (request.contentLength > 1024 * 1024) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          response.write(jsonEncode({'error': 'result_too_large'}));
        } else {
          final data = jsonDecode(await utf8.decoder.bind(request).join());
          final jobId = data is Map ? data['job_id'] : null;
          final job = _activeJob?.id == jobId ? _activeJob : _recentJobs[jobId];
          final id = data is Map ? data['client_id'] : null;
          if (job == null ||
              data is! Map ||
              data['job_id'] != job.id ||
              id is! String ||
              !job.clients.contains(id)) {
            response.statusCode = HttpStatus.conflict;
            response.write(jsonEncode({'error': 'job_not_active'}));
          } else if (data['complete'] == true) {
            job.completed.add(id);
            if (job.completed.length == job.clients.length &&
                !job.done.isCompleted) {
              job.done.complete();
            }
            _reconcileLateJob(job);
            response.write(jsonEncode({'completed': job.completed.length}));
          } else {
            final rawSamples = data['samples'];
            if (rawSamples is! List ||
                rawSamples.length > 100 ||
                rawSamples.any(
                  (raw) =>
                      raw is! Map ||
                      raw['request_id'] is! String ||
                      raw['success'] is! bool ||
                      raw['bytes_recibidos'] is! int ||
                      raw['timestamp_utc'] is! String,
                )) {
              response.statusCode = HttpStatus.badRequest;
              response.write(jsonEncode({'error': 'invalid_samples'}));
            } else {
              for (final raw in rawSamples.cast<Map>()) {
                repository.addMeasurement(
                  Measurement(
                    id: _uuid.v4(),
                    sessionId: job.session.id,
                    phaseId: job.phase.id,
                    testId: job.testId,
                    trialId: job.trialId,
                    requestId: raw['request_id'] as String,
                    scenarioId: job.config.scenarioId,
                    clients: job.config.clients,
                    distanceM:
                        job.serverDistances[id]?.meters ??
                        (raw['distancia_m'] as num?)?.toDouble(),
                    distanceSource: job.serverDistances[id]?.meters != null
                        ? 'server_${job.serverDistances[id]!.source}'
                        : raw['origen_distancia'] as String? ?? 'unknown',
                    distanceUncertaintyM:
                        job.serverDistances[id]?.meters != null
                        ? job.serverDistances[id]!.uncertaintyM
                        : (raw['incertidumbre_distancia_m'] as num?)
                              ?.toDouble(),
                    targetDistanceM: (raw['distancia_objetivo_m'] as num?)
                        ?.toDouble(),
                    environment: raw['ambiente'] as String? ?? 'unknown',
                    timestampUtc: DateTime.parse(
                      raw['timestamp_utc'] as String,
                    ),
                    success: raw['success'] as bool,
                    bytesReceived: raw['bytes_recibidos'] as int,
                    bytesSent: raw['bytes_enviados'] as int? ?? 0,
                    latencyMs: (raw['latencia_ms'] as num?)?.toDouble(),
                    jitterMs: (raw['jitter_ms'] as num?)?.toDouble(),
                    speedMbps: (raw['velocidad_mbps'] as num?)?.toDouble(),
                    httpStatus: raw['http_status'] as int?,
                    rssiDbm: raw['rssi_dbm'] as int?,
                    error: raw['error'] as String?,
                    warmup: raw['warmup'] == true,
                    protocol:
                        raw['protocolo'] as String? ?? job.config.protocol,
                    clientId: id,
                  ),
                );
              }
              _reconcileLateJob(job);
              response.write(jsonEncode({'accepted': rawSamples.length}));
            }
          }
        }
      } else if (request.uri.path == '/ping' && request.method == 'GET') {
        response.write(
          jsonEncode({
            'request_id': request.uri.queryParameters['id'] ?? _uuid.v4(),
            'utc': DateTime.now().toUtc().toIso8601String(),
            'protocol': protocolVersion,
          }),
        );
      } else if (request.uri.path == '/upload' && request.method == 'POST') {
        final size = int.tryParse(request.uri.queryParameters['bytes'] ?? '');
        if (size == null || size < 1 || size > maxDownloadBytes) {
          response.statusCode = HttpStatus.badRequest;
          response.write(jsonEncode({'error': 'invalid_size'}));
        } else if (_activeTransfers >= 4) {
          response.statusCode = HttpStatus.serviceUnavailable;
          response.write(jsonEncode({'error': 'capacity_reached'}));
        } else {
          _activeTransfers++;
          var bytes = 0;
          var invalid = false;
          try {
            await for (final chunk in request) {
              if (bytes + chunk.length > size) {
                invalid = true;
                break;
              }
              for (var j = 0; j < chunk.length; j++) {
                if (chunk[j] != ((bytes + j) % (64 * 1024)) % 251) {
                  invalid = true;
                }
              }
              bytes += chunk.length;
            }
          } finally {
            _activeTransfers--;
          }
          if (invalid || bytes != size) {
            response.statusCode = HttpStatus.badRequest;
            response.write(
              jsonEncode({'error': 'integrity_failure', 'received': bytes}),
            );
          } else {
            response.write(
              jsonEncode({'bytes_received': bytes, 'integrity': 'ok'}),
            );
          }
        }
      } else if (request.uri.path == '/download' && request.method == 'GET') {
        final size = int.tryParse(request.uri.queryParameters['bytes'] ?? '');
        if (size == null || size < 1 || size > maxDownloadBytes) {
          response.statusCode = HttpStatus.badRequest;
          response.write(
            jsonEncode({'error': 'invalid_size', 'max': maxDownloadBytes}),
          );
        } else if (_activeTransfers >= 4) {
          response.statusCode = HttpStatus.serviceUnavailable;
          response.write(jsonEncode({'error': 'capacity_reached'}));
        } else {
          _activeTransfers++;
          try {
            response.headers.contentType = ContentType.binary;
            response.contentLength = size;
            final block = List<int>.generate(64 * 1024, (i) => i % 251);
            var remaining = size;
            while (remaining > 0) {
              final length = min(remaining, block.length);
              response.add(
                length == block.length ? block : block.sublist(0, length),
              );
              remaining -= length;
              if (remaining % (1024 * 1024) < block.length) {
                await response.flush();
              }
            }
          } finally {
            _activeTransfers--;
          }
        }
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write(jsonEncode({'error': 'not_found'}));
      }
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.write(jsonEncode({'error': 'internal_error'}));
      } catch (_) {
        // The peer may have disconnected after headers were sent.
      }
    } finally {
      try {
        await response.close();
      } catch (_) {
        // A disconnected peer cannot receive the final response.
      }
    }
  }

  void _reconcileLateJob(_CoordinatedJob job) {
    if (identical(job, _activeJob) ||
        job.reconciled ||
        job.completed.length != job.clients.length ||
        repository.trialMeasurementCount(job.trialId) !=
            job.config.count * job.config.clients) {
      return;
    }
    job.reconciled = true;
    repository.finishTrial(job.trialId, 'finished');
    repository.addEvent(
      'coordinated_trial_recovered',
      sessionId: job.session.id,
      phaseId: job.phase.id,
      testId: job.testId,
      trialId: job.trialId,
    );
  }

  Future<Map<String, Object?>> probe(Uri base) async {
    await _validateLocal(base);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(base.resolve('/health'));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, Object?>;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>> register(Uri base, String code) async {
    await _validateLocal(base);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(base.resolve('/register'));
      request.headers.set('X-Lanxis-Code', code);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'client_id': clientId,
          if (_participantBeacon != null)
            'distance_beacon_token': _participantBeacon!.token,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw HttpException('Registro HTTP ${response.statusCode}: $body');
      }
      return jsonDecode(body) as Map<String, Object?>;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> startParticipant(Uri base, String code) async {
    if (_participating) return;
    try {
      _participantBeacon = await BleBeacon.start();
      participantBeaconError = null;
    } catch (error) {
      participantBeaconError = '$error';
    }
    try {
      await register(base, code);
      if (Platform.isAndroid) {
        await _participantService.invokeMethod<void>('start');
      }
    } catch (_) {
      await _participantBeacon?.close();
      _participantBeacon = null;
      rethrow;
    }
    lastParticipantError = null;
    _participating = true;
    _participantTask = _participantLoop(base, code);
  }

  Future<void> stopParticipant() async {
    _participating = false;
    await _participantTask;
    _participantTask = null;
    await _participantBeacon?.close();
    _participantBeacon = null;
    if (Platform.isAndroid) {
      await _participantService.invokeMethod<void>('stop');
    }
  }

  Future<void> _participantLoop(Uri base, String code) async {
    while (_participating) {
      try {
        try {
          await _drainResultOutbox(base, code);
        } catch (error) {
          lastParticipantError = '$error';
        }
        final work = await _exchange(base, code, '/work?client_id=$clientId');
        if (repository.pendingResults(base.toString()).isEmpty) {
          lastParticipantError = null;
        }
        final job = work['job'];
        if (job is Map<String, dynamic>) {
          await _performCoordinatedJob(base, code, job);
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        lastParticipantError = '$e';
        if (_participating) {
          try {
            await register(base, code);
          } catch (_) {
            // Retry after a server restart or transient network outage.
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
  }

  Future<void> _performCoordinatedJob(
    Uri base,
    String code,
    Map<String, dynamic> job,
  ) async {
    final delay = DateTime.parse(job['start_utc'] as String)
        .difference(DateTime.parse(job['server_utc'] as String));
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!_participating) return;
    final session = repository.createSession(
      'Participación: ${job['session_name']}',
      notes: 'Ensayo coordinado ${job['id']} del servidor ${base.host}',
    );
    final phase = repository.createPhase(
      session.id,
      job['phase_name'] as String,
    );
    final config = TrialConfig.fromJson(
      Map<String, Object?>.from(job['config'] as Map),
    );
    await runTrial(
      base: base,
      code: code,
      session: session,
      phase: phase,
      config: config,
      cancelled: () => !_participating,
      coordinated: true,
    );
    final samples = repository.measurements(session.id, includeWarmup: true);
    for (var i = 0; i < samples.length; i += 100) {
      repository.queueResult(
        base.toString(),
        jsonEncode({
          'job_id': job['id'],
          'client_id': clientId,
          'samples': samples.skip(i).take(100).map((m) => m.toJson()).toList(),
        }),
      );
    }
    repository.queueResult(
      base.toString(),
      jsonEncode({
        'job_id': job['id'],
        'client_id': clientId,
        'complete': true,
      }),
    );
    await _drainResultOutbox(base, code);
  }

  Future<void> _drainResultOutbox(Uri base, String code) async {
    for (final row in repository.pendingResults(base.toString())) {
      final id = row['id'] as String;
      final payload = Map<String, Object?>.from(
        jsonDecode(row['payload_json'] as String) as Map,
      );
      try {
        await _sendResultWithRetry(base, code, payload);
        repository.acknowledgeResult(id);
      } on HttpException catch (error) {
        if (!error.message.contains('409')) rethrow;
        repository.markResultRejected(id);
        lastParticipantError = 'El servidor ya no conserva el ensayo de un lote. La copia local permanece disponible.';
      }
    }
  }

  Future<void> _sendResultWithRetry(
    Uri base,
    String code,
    Map<String, Object?> body,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 5 && _participating; attempt++) {
      try {
        await _exchange(base, code, '/result', body: body);
        return;
      } catch (error) {
        lastError = error;
        if (error is HttpException && error.message.contains('409')) rethrow;
        if (attempt == 4) break;
        try {
          await register(base, code);
        } catch (_) {
          // The server may be unreachable until the next retry.
        }
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (1 << attempt)),
        );
      }
    }
    throw StateError(
      'Resultados conservados localmente; no se confirmó la sincronización: $lastError',
    );
  }

  Future<Map<String, dynamic>> _exchange(
    Uri base,
    String code,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = body == null
          ? await client.getUrl(base.resolve(path))
          : await client.postUrl(base.resolve(path));
      request.headers.set('X-Lanxis-Code', code);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw HttpException('Coordinación HTTP ${response.statusCode}: $text');
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<int> runCoordinatedTrial({
    required LabSession session,
    required LabPhase phase,
    required TrialConfig config,
  }) async {
    if (session.status != 'active' || phase.status != 'active') {
      throw StateError('La sesión y la fase deben estar activas');
    }
    if (!isServing || config.clients < 1 || _activeJob != null) {
      throw StateError(
        'Inicia el servidor y espera a que termine el ensayo actual',
      );
    }
    if (config.count < 1 ||
        config.count > 100000 ||
        config.payloadBytes < 0 ||
        config.payloadBytes > maxDownloadBytes ||
        (config.protocol == 'udp' &&
            config.payloadBytes > UdpEchoServer.maxPayloadBytes) ||
        config.timeoutMs < 100 ||
        !{'http', 'tcp', 'udp', 'udp-burst'}.contains(config.protocol) ||
        (['udp', 'udp-burst'].contains(config.protocol) &&
            config.direction != 'download') ||
        config.intervalMs < 0 ||
        !{'download', 'upload'}.contains(config.direction) ||
        (config.direction == 'upload' && config.payloadBytes == 0)) {
      throw ArgumentError('Configuración fuera de límites');
    }
    final now = DateTime.now().toUtc();
    final ready = _readyWorkers.entries
        .where((entry) => now.difference(entry.value).inSeconds < 8)
        .map((entry) => entry.key)
        .take(config.clients)
        .toSet();
    if (ready.length != config.clients) {
      throw StateError(
        'Se necesitan ${config.clients} participantes activos; hay ${ready.length}.',
      );
    }
    final serverDistances = <String, DistanceObservation>{};
    for (final id in ready) {
      final token = _clientBeaconTokens[id];
      if (token == null) continue;
      final observation = await distanceProbe.measure(
        Uri.parse('http://127.0.0.1'),
        beaconToken: token,
        environment: config.environment,
      );
      if (observation.meters != null) serverDistances[id] = observation;
    }
    final testId = repository.createTest(phase.id, config.scenarioId, config);
    final trialId = repository.startTrial(testId);
    final serverTimer = Stopwatch()..start();
    final job = _CoordinatedJob(
      id: _uuid.v4(),
      session: session,
      phase: phase,
      testId: testId,
      trialId: trialId,
      config: config,
      clients: ready,
      serverDistances: serverDistances,
    );
    _activeJob = job;
    repository.addEvent(
      'coordinated_trial_started',
      sessionId: session.id,
      phaseId: phase.id,
      testId: testId,
      trialId: trialId,
      metadataJson: jsonEncode({
        'client_ids': ready.toList(),
        'server_distance_m': {
          for (final entry in serverDistances.entries)
            entry.key: entry.value.meters,
        },
      }),
    );
    var status = 'finished';
    try {
      final estimatedMs =
          (config.count + config.warmup) *
              (config.timeoutMs + config.intervalMs) *
              2 +
          30000;
      await job.done.future.timeout(
        Duration(milliseconds: estimatedMs.clamp(60000, 3600000)),
      );
      final actual = repository.trialMeasurementCount(trialId);
      if (actual != config.count * config.clients) {
        status = 'incomplete';
      }
      return actual;
    } on TimeoutException {
      status = 'timeout';
      rethrow;
    } catch (_) {
      status = 'failed';
      rethrow;
    } finally {
      serverTimer.stop();
      final serverSamples = repository
          .measurements(session.id, includeWarmup: true)
          .where((m) => m.trialId == trialId)
          .toList();
      _activeJob = null;
      job.reconciled = status == 'finished';
      _recentJobs[job.id] = job;
      if (_recentJobs.length > 32) {
        _recentJobs.remove(_recentJobs.keys.first);
      }
      repository.finishTrial(trialId, status);
      repository.addEvent(
        'coordinated_trial_$status',
        sessionId: session.id,
        phaseId: phase.id,
        testId: testId,
        trialId: trialId,
        severity: status == 'finished' ? 'info' : 'warning',
        metadataJson: jsonEncode({
          'server_elapsed_ms': serverTimer.elapsedMilliseconds,
          'server_received_samples': serverSamples.length,
          'server_payload_sent_bytes': serverSamples.fold<int>(
            0,
            (sum, m) => sum + m.bytesReceived,
          ),
          'server_payload_received_bytes': serverSamples.fold<int>(
            0,
            (sum, m) => sum + m.bytesSent,
          ),
          'server_rss_bytes_end': ProcessInfo.currentRss,
          'server_distance_m': {
            for (final entry in serverDistances.entries)
              entry.key: entry.value.meters,
          },
        }),
      );
    }
  }

  Future<void> _validateLocal(Uri uri) async {
    if (uri.scheme != 'http' || uri.host.isEmpty) {
      throw ArgumentError('Use una URL HTTP de la red local');
    }
    final addresses = await InternetAddress.lookup(uri.host);
    if (addresses.isEmpty ||
        addresses.any((address) {
          final b = address.rawAddress;
          if (address.type == InternetAddressType.IPv4) {
            return !((b[0] == 10) ||
                (b[0] == 127) ||
                (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
                (b[0] == 192 && b[1] == 168) ||
                (b[0] == 169 && b[1] == 254));
          }
          return !((b[0] & 0xfe) == 0xfc ||
              (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) ||
              address.isLoopback);
        })) {
      throw ArgumentError(
        'LANXIS solo permite destinos privados o de enlace local',
      );
    }
  }

  Future<List<Measurement>> runTrial({
    required Uri base,
    required String code,
    required LabSession session,
    required LabPhase phase,
    required TrialConfig config,
    void Function(int completed, int total)? onProgress,
    bool Function()? cancelled,
    bool coordinated = false,
  }) async {
    lastUdpBurstResult = null;
    if (session.status != 'active' || phase.status != 'active') {
      throw StateError('La sesión y la fase deben estar activas');
    }
    await _validateLocal(base);
    if (code.length != 6) {
      throw ArgumentError('Código de emparejamiento inválido');
    }
    if (config.count < 1 ||
        config.count > 100000 ||
        config.payloadBytes < 0 ||
        config.payloadBytes > maxDownloadBytes ||
        ({'udp', 'udp-burst'}.contains(config.protocol) &&
            config.payloadBytes > UdpEchoServer.maxPayloadBytes) ||
        (config.protocol == 'udp-burst' &&
            (config.count + config.warmup > 1000 ||
                config.intervalMs > 1000)) ||
        config.intervalMs < 0 ||
        config.timeoutMs < 100 ||
        !{'http', 'tcp', 'udp', 'udp-burst'}.contains(config.protocol) ||
        ({'udp', 'udp-burst'}.contains(config.protocol) &&
            config.direction != 'download') ||
        !{'download', 'upload'}.contains(config.direction) ||
        (config.direction == 'upload' && config.payloadBytes == 0)) {
      throw ArgumentError('Configuración fuera de límites');
    }
    if (!coordinated &&
        (config.clients != 1 ||
            {'E4', 'E5', 'E6'}.contains(config.scenarioId))) {
      throw UnsupportedError(
        'Los escenarios multicliente requieren coordinación de varios dispositivos; una ejecución individual no puede etiquetarse como multicliente.',
      );
    }
    await register(base, code);
    final capabilities = await probe(base);
    final tcpPort = capabilities['tcp_port'] as int?;
    final udpPort = capabilities['udp_port'] as int?;
    if (config.protocol == 'tcp' && tcpPort == null) {
      throw UnsupportedError('Este servidor no ofrece transferencias TCP');
    }
    if ({'udp', 'udp-burst'}.contains(config.protocol) && udpPort == null) {
      throw UnsupportedError('Este servidor no ofrece eco UDP');
    }
    final observation = coordinated && config.distanceM == null
        ? const DistanceObservation(
            source: 'server_pending',
            reason: 'La distancia de este ensayo la mide el servidor.',
          )
        : config.distanceM == null
        ? await distanceProbe.measure(
            base,
            beaconToken: capabilities['distance_beacon_token'] as String?,
            environment: config.environment,
          )
        : DistanceObservation(
            meters: config.distanceM,
            source: config.distanceSource == 'unknown'
                ? 'manual'
                : config.distanceSource,
          );
    lastDistanceReason = observation.reason;
    final effectiveConfig = config.withDistance(
      observation.meters,
      observation.source,
      observation.uncertaintyM,
    );
    final testId = repository.createTest(
      phase.id,
      config.scenarioId,
      effectiveConfig,
    );
    final trialId = repository.startTrial(testId);
    if (!coordinated &&
        observation.meters == null &&
        observation.reason != null) {
      repository.addEvent(
        'distance_unavailable',
        sessionId: session.id,
        phaseId: phase.id,
        testId: testId,
        trialId: trialId,
        metadataJson: jsonEncode({'reason': observation.reason}),
      );
    }
    if (observation.source.startsWith('ble_rssi_estimate')) {
      repository.addEvent(
        'distance_estimated',
        sessionId: session.id,
        phaseId: phase.id,
        testId: testId,
        trialId: trialId,
        metadataJson: jsonEncode({
          'source': observation.source,
          'distance_m': observation.meters,
          'uncertainty_m': observation.uncertaintyM,
          'rssi_samples_dbm': observation.rssiSamplesDbm,
          'model': 'log_distance_uncalibrated_v1',
          'environment': config.environment,
        }),
      );
    }
    if (config.protocol == 'udp-burst') {
      return _runUdpBurst(
        base: base,
        code: code,
        session: session,
        phase: phase,
        config: effectiveConfig,
        testId: testId,
        trialId: trialId,
        udpPort: udpPort!,
        cancelled: cancelled,
        onProgress: onProgress,
      );
    }
    final client = HttpClient()
      ..connectionTimeout = Duration(milliseconds: config.timeoutMs);
    final results = <Measurement>[];
    double? previousRtt;
    var status = 'finished';
    try {
      for (var i = 0; i < config.count + config.warmup; i++) {
        if (cancelled?.call() ?? false) {
          status = 'cancelled';
          break;
        }
        final requestId = _uuid.v4();
        final stopwatch = Stopwatch()..start();
        int? httpStatus;
        int bytes = 0;
        int bytesSent = 0;
        String? error;
        var invalidPayload = false;
        final body = BytesBuilder(copy: false);
        try {
          if (config.protocol == 'tcp') {
            final sample = await TcpTransferClient.sample(
              host: base.host,
              port: tcpPort!,
              code: code,
              requestId: requestId,
              direction: config.direction,
              bytes: config.payloadBytes,
              timeout: Duration(milliseconds: config.timeoutMs),
              onBytesSent: (value) => bytesSent = value,
            );
            bytes = sample.bytesReceived;
            bytesSent = sample.bytesSent;
          } else if (config.protocol == 'udp') {
            final echoed = await UdpEchoClient.sample(
              host: base.host,
              port: udpPort!,
              code: code,
              requestId: requestId,
              payloadBytes: config.payloadBytes,
              timeout: Duration(milliseconds: config.timeoutMs),
              onSent: (value) => bytesSent = value,
            );
            bytes = echoed;
          } else {
            final upload = config.direction == 'upload';
            final uri = base.resolve(
              upload
                  ? '/upload?bytes=${config.payloadBytes}'
                  : config.payloadBytes > 0
                  ? '/download?bytes=${config.payloadBytes}'
                  : '/ping?id=$requestId',
            );
            final request =
                await (upload ? client.postUrl(uri) : client.getUrl(uri))
                    .timeout(Duration(milliseconds: config.timeoutMs));
            request.headers.set('X-Lanxis-Code', code);
            if (upload) {
              request.contentLength = config.payloadBytes;
              final block = List<int>.generate(64 * 1024, (j) => j % 251);
              while (bytesSent < config.payloadBytes) {
                final length = min(
                  block.length,
                  config.payloadBytes - bytesSent,
                );
                request.add(
                  length == block.length ? block : block.sublist(0, length),
                );
                bytesSent += length;
                if (bytesSent % (1024 * 1024) < block.length) {
                  await request.flush().timeout(
                    Duration(milliseconds: config.timeoutMs),
                  );
                }
              }
            }
            final response = await request.close().timeout(
              Duration(milliseconds: config.timeoutMs),
            );
            httpStatus = response.statusCode;
            await for (final chunk in response.timeout(
              Duration(milliseconds: config.timeoutMs),
            )) {
              if (!upload &&
                  config.payloadBytes > 0 &&
                  bytes + chunk.length > config.payloadBytes) {
                throw StateError('La descarga excedió el tamaño solicitado');
              }
              if ((upload || config.payloadBytes == 0) &&
                  body.length + chunk.length > 4096) {
                throw StateError('La respuesta excedió 4 KiB');
              }
              if (response.statusCode == 200 &&
                  !upload &&
                  config.payloadBytes > 0) {
                for (var j = 0; j < chunk.length; j++) {
                  if (chunk[j] != ((bytes + j) % (64 * 1024)) % 251) {
                    invalidPayload = true;
                  }
                }
              } else if (upload || config.payloadBytes == 0) {
                body.add(chunk);
              }
              bytes += chunk.length;
            }
            if (response.statusCode != 200) {
              error = 'HTTP ${response.statusCode}';
            } else if (upload) {
              final data = jsonDecode(utf8.decode(body.takeBytes()));
              if (data is! Map ||
                  data['bytes_received'] != config.payloadBytes ||
                  data['integrity'] != 'ok') {
                error = 'La subida no pasó la verificación de integridad';
              }
            } else if (config.payloadBytes > 0 &&
                (invalidPayload || bytes != config.payloadBytes)) {
              error = 'La transferencia no pasó la verificación de integridad';
            } else if (config.payloadBytes == 0) {
              final data = jsonDecode(utf8.decode(body.takeBytes()));
              if (data is! Map ||
                  data['request_id'] != requestId ||
                  data['protocol'] != protocolVersion) {
                error = 'Respuesta de ping no coincide con la petición';
              }
            }
          }
        } catch (e) {
          error = e.toString();
        }
        stopwatch.stop();
        final success = error == null;
        final rtt = success ? stopwatch.elapsedMicroseconds / 1000.0 : null;
        final jitter = rtt != null && previousRtt != null
            ? (rtt - previousRtt).abs()
            : null;
        if (rtt != null) previousRtt = rtt;
        final speed =
            success &&
                config.protocol != 'udp' &&
                config.payloadBytes > 0 &&
                (config.direction == 'upload' ? bytesSent : bytes) > 0 &&
                stopwatch.elapsedMicroseconds > 0
            ? (config.direction == 'upload' ? bytesSent : bytes) *
                  8 /
                  stopwatch.elapsedMicroseconds
            : null;
        final item = Measurement(
          id: _uuid.v4(),
          sessionId: session.id,
          phaseId: phase.id,
          testId: testId,
          trialId: trialId,
          requestId: requestId,
          scenarioId: config.scenarioId,
          clients: config.clients,
          distanceM: effectiveConfig.distanceM,
          distanceSource: effectiveConfig.distanceSource,
          distanceUncertaintyM: effectiveConfig.distanceUncertaintyM,
          targetDistanceM: effectiveConfig.targetDistanceM,
          environment: effectiveConfig.environment,
          timestampUtc: DateTime.now().toUtc(),
          success: success,
          bytesReceived: bytes,
          bytesSent: bytesSent,
          latencyMs: rtt,
          jitterMs: jitter,
          speedMbps: speed,
          httpStatus: httpStatus,
          // This column is reserved for Wi-Fi signal measurements. BLE RSSI
          // is provenance for distance only, stored in distance_estimated.
          rssiDbm: null,
          error: error,
          warmup: i < config.warmup,
          protocol: config.protocol,
          clientId: clientId,
        );
        repository.addMeasurement(item);
        if (!item.warmup) {
          results.add(item);
          onProgress?.call(results.length, config.count);
        }
        if (i < config.count + config.warmup - 1 && config.intervalMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: config.intervalMs));
        }
      }
    } catch (_) {
      status = 'failed';
      rethrow;
    } finally {
      client.close(force: true);
      repository.finishTrial(trialId, status);
      repository.addEvent(
        'trial_$status',
        sessionId: session.id,
        phaseId: phase.id,
        testId: testId,
        trialId: trialId,
        severity: status == 'failed' ? 'error' : 'info',
      );
    }
    return results;
  }

  Future<List<Measurement>> _runUdpBurst({
    required Uri base,
    required String code,
    required LabSession session,
    required LabPhase phase,
    required TrialConfig config,
    required String testId,
    required String trialId,
    required int udpPort,
    required bool Function()? cancelled,
    required void Function(int completed, int total)? onProgress,
  }) async {
    var status = 'finished';
    final results = <Measurement>[];
    try {
      final burst = await UdpEchoClient.burst(
        host: base.host,
        port: udpPort,
        code: code,
        requestIds: [
          for (var i = 0; i < config.count + config.warmup; i++) _uuid.v4(),
        ],
        payloadBytes: config.payloadBytes,
        timeout: Duration(milliseconds: config.timeoutMs),
        intervalMs: config.intervalMs,
        cancelled: cancelled,
        onSent: (sent, _) => onProgress?.call(
          (sent - config.warmup).clamp(0, config.count),
          config.count,
        ),
      );
      lastUdpBurstResult = burst;
      if (burst.cancelled) status = 'cancelled';
      double? previousRtt;
      for (var i = 0; i < burst.packets.length; i++) {
        final packet = burst.packets[i];
        final rtt = packet.latencyMs;
        final jitter = rtt != null && previousRtt != null
            ? (rtt - previousRtt).abs()
            : null;
        if (rtt != null) previousRtt = rtt;
        final item = Measurement(
          id: _uuid.v4(),
          sessionId: session.id,
          phaseId: phase.id,
          testId: testId,
          trialId: trialId,
          requestId: packet.requestId,
          scenarioId: config.scenarioId,
          clients: config.clients,
          distanceM: config.distanceM,
          distanceSource: config.distanceSource,
          distanceUncertaintyM: config.distanceUncertaintyM,
          targetDistanceM: config.targetDistanceM,
          environment: config.environment,
          timestampUtc: packet.sentUtc,
          success: packet.received,
          bytesReceived: packet.receivedBytes,
          bytesSent: packet.sentBytes,
          latencyMs: rtt,
          jitterMs: jitter,
          speedMbps: null,
          httpStatus: null,
          rssiDbm: null,
          error: packet.received
              ? null
              : 'Sin eco UDP dentro de ${config.timeoutMs} ms',
          warmup: i < config.warmup,
          protocol: 'udp-burst',
          clientId: clientId,
        );
        repository.addMeasurement(item);
        if (!item.warmup) {
          results.add(item);
        }
      }
      repository.addEvent(
        'udp_burst_summary',
        sessionId: session.id,
        phaseId: phase.id,
        testId: testId,
        trialId: trialId,
        metadataJson: jsonEncode({
          'sent': burst.packets.length,
          'received': burst.packets.length - burst.lost,
          'lost': burst.lost,
          'reordered': burst.reordered,
          'duplicates': burst.duplicates,
          'invalid': burst.invalid,
          'interval_ms': config.intervalMs,
          'packets': [
            for (var i = 0; i < burst.packets.length; i++)
              {
                'send_index': i,
                'request_id': burst.packets[i].requestId,
                'receive_order': burst.packets[i].receiveOrder,
              },
          ],
        }),
      );
      return results;
    } catch (_) {
      status = 'failed';
      rethrow;
    } finally {
      repository.finishTrial(trialId, status);
      repository.addEvent(
        'trial_$status',
        sessionId: session.id,
        phaseId: phase.id,
        testId: testId,
        trialId: trialId,
        severity: status == 'failed' ? 'error' : 'info',
      );
    }
  }
}
