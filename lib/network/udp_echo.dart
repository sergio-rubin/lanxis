import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Echoes one authenticated, bounded datagram without amplifying its size.
class UdpEchoServer {
  UdpEchoServer(this.code);
  final String code;
  static const maxPayloadBytes = 1024;
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;

  int? get port => _socket?.port;

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket = socket;
    _subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = socket.receive()) != null) {
        final bytes = packet!.data;
        if (bytes.length > 1152) continue;
        final separator = bytes.indexOf(10);
        if (separator < 0 ||
            separator > 128 ||
            bytes.length - separator - 1 > maxPayloadBytes) {
          continue;
        }
        try {
          final parts = ascii.decode(bytes.sublist(0, separator)).split(' ');
          if (parts.length != 3 ||
              parts[0] != 'LANXIS/1' ||
              parts[1] != code ||
              parts[2].length != 36) {
            continue;
          }
          socket.send(bytes, packet.address, packet.port);
        } on FormatException {
          // Ignore unrelated or malformed local network datagrams.
        }
      }
    });
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }
}

class UdpEchoClient {
  static List<int> _packet(String code, String requestId, int payloadBytes) => [
    ...ascii.encode('LANXIS/1 $code $requestId\n'),
    for (var i = 0; i < payloadBytes; i++) i % 251,
  ];

  static Future<int> sample({
    required String host,
    required int port,
    required String code,
    required String requestId,
    required int payloadBytes,
    required Duration timeout,
    void Function(int)? onSent,
  }) async {
    if (payloadBytes < 0 || payloadBytes > UdpEchoServer.maxPayloadBytes) {
      throw ArgumentError.value(payloadBytes, 'payloadBytes');
    }
    final addresses = await InternetAddress.lookup(host);
    final address = addresses
        .where((a) => a.type == InternetAddressType.IPv4)
        .firstOrNull;
    if (address == null) {
      throw UnsupportedError('UDP requiere una dirección IPv4 local');
    }
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final packet = _packet(code, requestId, payloadBytes);
    final response = Completer<int>();
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        if (datagram!.port == port &&
            datagram.address.address == address.address &&
            datagram.data.length == packet.length) {
          var valid = true;
          for (var i = 0; i < packet.length; i++) {
            if (packet[i] != datagram.data[i]) {
              valid = false;
              break;
            }
          }
          if (valid && !response.isCompleted) {
            response.complete(datagram.data.length);
          }
        }
      }
    });
    try {
      final sent = socket.send(packet, address, port);
      onSent?.call(sent);
      if (sent != packet.length) {
        throw StateError('El datagrama UDP no se pudo enviar completo');
      }
      return await response.future.timeout(timeout);
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  /// Sends a bounded burst on one socket and records the actual echo order.
  static Future<UdpBurstResult> burst({
    required String host,
    required int port,
    required String code,
    required List<String> requestIds,
    required int payloadBytes,
    required Duration timeout,
    int intervalMs = 0,
    bool Function()? cancelled,
    void Function(int sent, int total)? onSent,
  }) async {
    if (requestIds.isEmpty || requestIds.length > 1000) {
      throw ArgumentError.value(requestIds.length, 'requestIds.length');
    }
    if (requestIds.toSet().length != requestIds.length ||
        requestIds.any((id) => id.length != 36)) {
      throw ArgumentError('Cada datagrama necesita un UUID distinto');
    }
    if (payloadBytes < 0 ||
        payloadBytes > UdpEchoServer.maxPayloadBytes ||
        intervalMs < 0 ||
        intervalMs > 1000 ||
        timeout.inMilliseconds < 100) {
      throw ArgumentError('Parámetros de ráfaga UDP fuera de límites');
    }
    final addresses = await InternetAddress.lookup(host);
    final address = addresses
        .where((item) => item.type == InternetAddressType.IPv4)
        .firstOrNull;
    if (address == null) {
      throw UnsupportedError('UDP requiere una dirección IPv4 local');
    }
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final expected = [
      for (final id in requestIds) _packet(code, id, payloadBytes),
    ];
    final byId = {
      for (var index = 0; index < requestIds.length; index++)
        requestIds[index]: index,
    };
    final sentAt = List<int?>.filled(requestIds.length, null);
    final sentUtc = List<DateTime?>.filled(requestIds.length, null);
    final sentBytes = List<int>.filled(requestIds.length, 0);
    final receivedBytes = List<int>.filled(requestIds.length, 0);
    final rttMicros = List<int?>.filled(requestIds.length, null);
    final receiveOrder = List<int?>.filled(requestIds.length, null);
    final stopwatch = Stopwatch()..start();
    final allReceived = Completer<void>();
    var sentCount = 0;
    var accepted = 0;
    var duplicates = 0;
    var invalid = 0;
    var reordered = 0;
    var highestIndex = -1;
    var sendingDone = false;
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final reply = datagram!;
        if (reply.port != port || reply.address.address != address.address) {
          continue;
        }
        final separator = reply.data.indexOf(10);
        if (separator < 0 || separator > 128) {
          invalid++;
          continue;
        }
        List<String> parts;
        try {
          parts = ascii.decode(reply.data.sublist(0, separator)).split(' ');
        } on FormatException {
          invalid++;
          continue;
        }
        if (parts.length != 3 || parts[0] != 'LANXIS/1' || parts[1] != code) {
          invalid++;
          continue;
        }
        final index = byId[parts[2]];
        if (index == null || index >= sentCount) {
          invalid++;
          continue;
        }
        final payload = expected[index];
        if (reply.data.length != payload.length) {
          invalid++;
          continue;
        }
        var matches = true;
        for (var byte = 0; byte < payload.length; byte++) {
          if (reply.data[byte] != payload[byte]) {
            matches = false;
            break;
          }
        }
        if (!matches) {
          invalid++;
          continue;
        }
        if (receiveOrder[index] != null) {
          duplicates++;
          continue;
        }
        final elapsed = stopwatch.elapsedMicroseconds - sentAt[index]!;
        if (elapsed > timeout.inMicroseconds) continue;
        receiveOrder[index] = accepted++;
        receivedBytes[index] = reply.data.length;
        rttMicros[index] = elapsed;
        if (index < highestIndex) {
          reordered++;
        } else {
          highestIndex = index;
        }
        if (sendingDone && accepted == sentCount && !allReceived.isCompleted) {
          allReceived.complete();
        }
      }
    });
    try {
      for (var index = 0; index < requestIds.length; index++) {
        if (cancelled?.call() ?? false) break;
        sentAt[index] = stopwatch.elapsedMicroseconds;
        sentUtc[index] = DateTime.now().toUtc();
        sentCount++;
        sentBytes[index] = socket.send(expected[index], address, port);
        if (sentBytes[index] != expected[index].length) {
          throw StateError(
            'El datagrama UDP $index no se pudo enviar completo',
          );
        }
        onSent?.call(sentCount, requestIds.length);
        if (index < requestIds.length - 1 && intervalMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: intervalMs));
        } else if (index % 32 == 31) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      sendingDone = true;
      if (accepted != sentCount && sentCount > 0) {
        await Future.any([allReceived.future, Future<void>.delayed(timeout)]);
      }
      return UdpBurstResult(
        packets: [
          for (var index = 0; index < sentCount; index++)
            UdpBurstPacket(
              requestId: requestIds[index],
              sentUtc: sentUtc[index]!,
              sentBytes: sentBytes[index],
              receivedBytes: receivedBytes[index],
              latencyMs: rttMicros[index] == null
                  ? null
                  : rttMicros[index]! / 1000.0,
              receiveOrder: receiveOrder[index],
            ),
        ],
        reordered: reordered,
        duplicates: duplicates,
        invalid: invalid,
        cancelled: sentCount < requestIds.length,
      );
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }
}

class UdpBurstPacket {
  const UdpBurstPacket({
    required this.requestId,
    required this.sentUtc,
    required this.sentBytes,
    required this.receivedBytes,
    required this.latencyMs,
    required this.receiveOrder,
  });
  final String requestId;
  final DateTime sentUtc;
  final int sentBytes;
  final int receivedBytes;
  final double? latencyMs;
  final int? receiveOrder;
  bool get received => latencyMs != null;
}

class UdpBurstResult {
  const UdpBurstResult({
    required this.packets,
    required this.reordered,
    required this.duplicates,
    required this.invalid,
    required this.cancelled,
  });
  final List<UdpBurstPacket> packets;
  final int reordered;
  final int duplicates;
  final int invalid;
  final bool cancelled;
  int get lost => packets.where((packet) => !packet.received).length;
}
