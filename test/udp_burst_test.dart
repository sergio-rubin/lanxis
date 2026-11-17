import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/network/udp_echo.dart';

void main() {
  const ids = [
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000003',
  ];

  test('UDP burst records real echo replies from one socket', () async {
    final server = UdpEchoServer('123456');
    await server.start();
    addTearDown(server.close);
    final result = await UdpEchoClient.burst(
      host: '127.0.0.1',
      port: server.port!,
      code: '123456',
      requestIds: ids,
      payloadBytes: 32,
      timeout: const Duration(milliseconds: 500),
    );
    expect(result.packets, hasLength(3));
    expect(result.lost, 0);
    expect(result.packets.every((packet) => packet.received), isTrue);
    expect(result.packets.every((packet) => packet.sentBytes == 85), isTrue);
    expect(
      result.packets.every((packet) => packet.receivedBytes == 85),
      isTrue,
    );
  });

  test('UDP burst distinguishes loss and reordered arrivals', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(server.close);
    final received = <Datagram>[];
    final subscription = server.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = server.receive()) != null) {
        received.add(datagram!);
        if (received.length == 3) {
          final last = received[2];
          final first = received[0];
          server.send(last.data, last.address, last.port);
          server.send(first.data, first.address, first.port);
        }
      }
    });
    addTearDown(subscription.cancel);
    final result = await UdpEchoClient.burst(
      host: '127.0.0.1',
      port: server.port,
      code: '123456',
      requestIds: ids,
      payloadBytes: 0,
      timeout: const Duration(milliseconds: 300),
    );
    expect(result.packets.map((packet) => packet.received), [
      true,
      false,
      true,
    ]);
    expect(result.packets[2].receiveOrder, 0);
    expect(result.packets[0].receiveOrder, 1);
    expect(result.lost, 1);
    expect(result.reordered, 1);
    expect(result.duplicates, 0);
    expect(result.invalid, 0);
  });
}
