import 'dart:async';

import 'package:dbus/dbus.dart';

import 'ble_beacon.dart';

/// Reads the LANXIS advertisement that matches the server's health token.
/// Bluetooth remains a ranging aid; it never carries the trial traffic.
class LinuxBleScanner {
  const LinuxBleScanner();

  Future<List<int>> sample(String token) async {
    final expected = _decodeToken(token);
    if (expected == null) {
      throw const FormatException('Identificador de baliza BLE inválido.');
    }
    final bus = DBusClient.system();
    StreamSubscription<DBusSignal>? subscription;
    DBusRemoteObject? adapter;
    var discovering = false;
    Timer? settlingTimer;
    final samples = <int>[];
    final cached = <DBusObjectPath, Map<String, DBusValue>>{};
    final completed = Completer<void>();

    void record(DBusObjectPath path, Map<String, DBusValue> update) {
      final properties = cached.putIfAbsent(path, () => {});
      properties.addAll(update);
      if (!_matchesToken(properties['ServiceData'], expected)) return;
      final rssi =
          update['RSSI'] ??
          (update.containsKey('ServiceData') ? properties['RSSI'] : null);
      if (rssi is! DBusInt16 || rssi.value < -110 || rssi.value > -20) {
        return;
      }
      samples.add(rssi.value);
      settlingTimer ??= Timer(const Duration(seconds: 4), () {
        if (!completed.isCompleted) completed.complete();
      });
      if (samples.length >= 12 && !completed.isCompleted) completed.complete();
    }

    try {
      final manager = DBusRemoteObjectManager(
        bus,
        name: 'org.bluez',
        path: DBusObjectPath('/'),
      );
      final objects = await manager.getManagedObjects();
      final adapterPath = objects.entries
          .where((entry) => entry.value.containsKey('org.bluez.Adapter1'))
          .map((entry) => entry.key)
          .firstOrNull;
      if (adapterPath == null) {
        throw StateError('BlueZ no encontró un adaptador Bluetooth.');
      }
      adapter = DBusRemoteObject(bus, name: 'org.bluez', path: adapterPath);
      subscription = manager.signals.listen((signal) {
        if (signal is DBusObjectManagerInterfacesAddedSignal) {
          final properties =
              signal.interfacesAndProperties['org.bluez.Device1'];
          if (properties != null) record(signal.changedPath, properties);
        } else if (signal is DBusPropertiesChangedSignal &&
            signal.propertiesInterface == 'org.bluez.Device1') {
          record(signal.path, signal.changedProperties);
        } else if (signal is DBusObjectManagerInterfacesRemovedSignal &&
            signal.interfaces.contains('org.bluez.Device1')) {
          cached.remove(signal.changedPath);
        }
      });
      await adapter.callMethod('org.bluez.Adapter1', 'SetDiscoveryFilter', [
        DBusDict.stringVariant({
          'Transport': DBusString('le'),
          'DuplicateData': DBusBoolean(true),
        }),
      ], replySignature: DBusSignature(''));
      await adapter.callMethod(
        'org.bluez.Adapter1',
        'StartDiscovery',
        [],
        replySignature: DBusSignature(''),
      );
      discovering = true;
      // Include a previously discovered matching device only after discovery
      // starts; a new random token prevents accepting a former trial's beacon.
      for (final entry in objects.entries) {
        final properties = entry.value['org.bluez.Device1'];
        if (properties != null) record(entry.key, properties);
      }
      await completed.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
      return samples;
    } finally {
      settlingTimer?.cancel();
      await subscription?.cancel();
      if (discovering) {
        try {
          await adapter?.callMethod(
            'org.bluez.Adapter1',
            'StopDiscovery',
            [],
            replySignature: DBusSignature(''),
          );
        } catch (_) {
          // Bluetooth may have been disabled while scanning.
        }
      }
      await bus.close();
    }
  }

  static List<int>? _decodeToken(String token) {
    if (!RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(token)) return null;
    return List.generate(
      6,
      (index) =>
          int.parse(token.substring(index * 2, index * 2 + 2), radix: 16),
    );
  }

  static bool _matchesToken(DBusValue? serviceData, List<int> expected) {
    if (serviceData == null) return false;
    try {
      final entries = serviceData.asStringVariantDict();
      for (final entry in entries.entries) {
        if (entry.key.toLowerCase() != BleBeacon.serviceUuid) continue;
        final bytes = entry.value.asByteArray().toList();
        if (bytes.length != expected.length) return false;
        for (var index = 0; index < bytes.length; index++) {
          if (bytes[index] != expected[index]) return false;
        }
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}
