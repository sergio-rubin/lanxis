import 'dart:io';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

/// Advertisement only identifies the already paired LANXIS server.
/// It does not carry measurements or replace the Wi-Fi data connection.
class BleBeacon {
  BleBeacon._(this.token, this._stop);

  static const serviceUuid = 'a7f58c20-ff3b-4f92-b11a-17f855bc6049';
  static const _android = MethodChannel('mx.lanxis/distance');
  final Future<void> Function() _stop;
  final String token;

  static Future<BleBeacon> start() async {
    final bytes = List<int>.generate(6, (_) => Random.secure().nextInt(256));
    final token = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    if (Platform.isAndroid) {
      await _android.invokeMethod<void>('startBeacon', {'token': token});
      return BleBeacon._(
        token,
        () => _android.invokeMethod<void>('stopBeacon'),
      );
    }
    if (!Platform.isLinux) {
      throw UnsupportedError(
        'Publicidad BLE no disponible en esta plataforma.',
      );
    }
    final bus = DBusClient.system();
    try {
      final objects = await DBusRemoteObjectManager(
        bus,
        name: 'org.bluez',
        path: DBusObjectPath('/'),
      ).getManagedObjects();
      final adapter = objects.entries
          .where(
            (entry) =>
                entry.value.containsKey('org.bluez.LEAdvertisingManager1'),
          )
          .firstOrNull;
      if (adapter == null) {
        throw StateError('BlueZ no ofrece publicidad Bluetooth LE.');
      }
      final advertisement = _LanxisAdvertisement(bytes);
      await bus.registerObject(advertisement);
      final manager = DBusRemoteObject(
        bus,
        name: 'org.bluez',
        path: adapter.key,
      );
      try {
        await manager.callMethod(
          'org.bluez.LEAdvertisingManager1',
          'RegisterAdvertisement',
          [advertisement.path, DBusDict.stringVariant({})],
          replySignature: DBusSignature(''),
        );
      } catch (_) {
        await bus.unregisterObject(advertisement);
        rethrow;
      }
      return BleBeacon._(token, () async {
        try {
          await manager.callMethod(
            'org.bluez.LEAdvertisingManager1',
            'UnregisterAdvertisement',
            [advertisement.path],
            replySignature: DBusSignature(''),
          );
        } catch (_) {
          // BlueZ may already have removed the advertisement.
        }
        await bus.unregisterObject(advertisement);
        await bus.close();
      });
    } catch (_) {
      await bus.close();
      rethrow;
    }
  }

  Future<void> close() => _stop();
}

class _LanxisAdvertisement extends DBusObject {
  _LanxisAdvertisement(this.bytes)
    : super(DBusObjectPath('/mx/lanxis/distance_beacon'));

  final List<int> bytes;
  static const interface = 'org.bluez.LEAdvertisement1';

  Map<String, DBusValue> get properties => {
    'Type': DBusString('broadcast'),
    'ServiceData': DBusDict.stringVariant({
      BleBeacon.serviceUuid: DBusArray(
        DBusSignature('y'),
        bytes.map(DBusByte.new),
      ),
    }),
  };

  @override
  Future<DBusMethodResponse> getProperty(String name, String property) async {
    if (name != interface) return DBusMethodErrorResponse.unknownInterface();
    final value = properties[property];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String name) async =>
      name == interface
      ? DBusGetAllPropertiesResponse(properties)
      : DBusMethodErrorResponse.unknownInterface();

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async =>
      call.interface == interface && call.name == 'Release'
      ? DBusMethodSuccessResponse()
      : DBusMethodErrorResponse.unknownMethod();
}
