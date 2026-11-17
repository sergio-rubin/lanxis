import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A bounded, one-request-per-connection TCP engine. Framing is documented in
/// PROTOCOL.md. It measures the complete connection and transfer on the client.
class TcpTransferServer {
  TcpTransferServer(this.code, this.maxBytes);

  final String code;
  final int maxBytes;
  ServerSocket? _server;
  int _active = 0;
  final Set<Socket> _connections = {};

  int? get port => _server?.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server!.listen((socket) {
      if (_active >= 4) {
        socket.write('ERR capacity\n');
        unawaited(socket.flush().then((_) => socket.close()));
        return;
      }
      _active++;
      _connections.add(socket);
      unawaited(
        _handle(socket).whenComplete(() {
          _active--;
          _connections.remove(socket);
          socket.destroy();
        }),
      );
    });
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
    for (final socket in _connections.toList()) {
      socket.destroy();
    }
    _connections.clear();
  }

  Future<void> _handle(Socket socket) async {
    final header = <int>[];
    var parsed = false;
    var upload = false;
    var expected = 0;
    var received = 0;
    var invalid = false;
    var requestId = '';
    try {
      await for (final chunk in socket.timeout(const Duration(seconds: 30))) {
        var offset = 0;
        if (!parsed) {
          final newline = chunk.indexOf(10);
          if (newline < 0) {
            header.addAll(chunk);
            if (header.length > 256) throw const FormatException('header');
            continue;
          }
          header.addAll(chunk.take(newline));
          if (header.length > 256) throw const FormatException('header');
          final parts = ascii.decode(header).split(' ');
          if (parts.length != 5 ||
              parts[0] != 'LANXIS/1' ||
              parts[1] != code ||
              parts[2].length != 36 ||
              !{'download', 'upload'}.contains(parts[3])) {
            throw const FormatException('handshake');
          }
          expected = int.tryParse(parts[4]) ?? -1;
          upload = parts[3] == 'upload';
          if (expected < 0 ||
              expected > maxBytes ||
              (upload && expected == 0)) {
            throw const FormatException('size');
          }
          requestId = parts[2];
          parsed = true;
          offset = newline + 1;
          if (!upload) {
            socket.write('OK $requestId $expected\n');
            final block = List<int>.generate(64 * 1024, (i) => i % 251);
            var sent = 0;
            while (sent < expected) {
              final length = min(block.length, expected - sent);
              socket.add(
                length == block.length ? block : block.sublist(0, length),
              );
              sent += length;
              if (sent % (1024 * 1024) < block.length) {
                await socket.flush();
              }
            }
            await socket.flush();
            await socket.close();
            return;
          }
        }
        if (upload) {
          for (var i = offset; i < chunk.length; i++) {
            if (received >= expected ||
                chunk[i] != (received % (64 * 1024)) % 251) {
              invalid = true;
            }
            received++;
          }
          if (received >= expected) {
            socket.write(
              invalid || received != expected
                  ? 'ERR integrity\n'
                  : 'OK $requestId $received\n',
            );
            await socket.flush();
            await socket.close();
            return;
          }
        }
      }
    } catch (error) {
      try {
        socket.write(
          'ERR ${error is FormatException ? error.message : 'transfer'}\n',
        );
        await socket.flush();
      } catch (_) {
        // The peer may already have closed the connection.
      }
    }
  }
}

class TcpSample {
  const TcpSample(this.bytesReceived, this.bytesSent);
  final int bytesReceived;
  final int bytesSent;
}

class TcpTransferClient {
  static Future<TcpSample> sample({
    required String host,
    required int port,
    required String code,
    required String requestId,
    required String direction,
    required int bytes,
    required Duration timeout,
    void Function(int)? onBytesSent,
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    var sent = 0;
    var received = 0;
    try {
      socket.write('LANXIS/1 $code $requestId $direction $bytes\n');
      if (direction == 'upload') {
        final block = List<int>.generate(64 * 1024, (i) => i % 251);
        while (sent < bytes) {
          final length = min(block.length, bytes - sent);
          socket.add(length == block.length ? block : block.sublist(0, length));
          sent += length;
          onBytesSent?.call(sent);
          if (sent % (1024 * 1024) < block.length) {
            await socket.flush().timeout(timeout);
          }
        }
      }
      await socket.flush().timeout(timeout);
      final header = <int>[];
      var headerRead = false;
      await for (final chunk in socket.timeout(timeout)) {
        var offset = 0;
        if (!headerRead) {
          final newline = chunk.indexOf(10);
          if (newline < 0) {
            header.addAll(chunk);
            if (header.length > 256) {
              throw const FormatException('TCP response header');
            }
            continue;
          }
          header.addAll(chunk.take(newline));
          if (header.length > 256) {
            throw const FormatException('TCP response header');
          }
          final response = ascii.decode(header).split(' ');
          if (response.length != 3 ||
              response[0] != 'OK' ||
              response[1] != requestId ||
              int.tryParse(response[2]) != bytes) {
            throw StateError('Respuesta TCP inválida: ${ascii.decode(header)}');
          }
          headerRead = true;
          offset = newline + 1;
          if (direction == 'upload' || bytes == 0) {
            return TcpSample(0, sent);
          }
        }
        for (var i = offset; i < chunk.length; i++) {
          if (received >= bytes || chunk[i] != (received % (64 * 1024)) % 251) {
            throw StateError(
              'La descarga TCP no pasó la verificación de integridad',
            );
          }
          received++;
        }
        if (received == bytes) return TcpSample(received, sent);
      }
      throw StateError('Transferencia TCP incompleta');
    } finally {
      socket.destroy();
    }
  }
}
