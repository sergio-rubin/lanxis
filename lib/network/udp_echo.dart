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
    final packet = <int>[
      ...ascii.encode('LANXIS/1 $code $requestId\n'),
      for (var i = 0; i < payloadBytes; i++) i % 251,
    ];
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
}
