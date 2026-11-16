import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

class HotspotState {
  const HotspotState({
    required this.supported,
    required this.active,
    this.ssid,
    this.passphrase,
    this.reason,
  });
  final bool supported;
  final bool active;
  final String? ssid;
  final String? passphrase;
  final String? reason;
}

abstract interface class HotspotAdapter {
  Future<HotspotState> status();
  Future<HotspotState> start();
  Future<HotspotState> stop();
  Future<void> openSystemWifiSettings();
}

class PlatformHotspotAdapter implements HotspotAdapter {
  const PlatformHotspotAdapter();
  static const _channel = MethodChannel('mx.lanxis/hotspot');
  static String? _linuxProfile;
  static String? _linuxPassword;

  @override
  Future<HotspotState> status() async {
    if (Platform.isLinux) return _linuxStatus();
    if (!Platform.isAndroid) {
      return const HotspotState(
        supported: false,
        active: false,
        reason: 'Usa una LAN existente o configura el hotspot en el sistema.',
      );
    }
    final response = await _channel.invokeMapMethod<String, Object?>('status');
    return _parse(response);
  }

  @override
  Future<HotspotState> start() async {
    if (Platform.isLinux) return _linuxStart();
    if (!Platform.isAndroid) return status();
    final response = await _channel.invokeMapMethod<String, Object?>('start');
    return _parse(response);
  }

  @override
  Future<HotspotState> stop() async {
    if (Platform.isLinux) return _linuxStop();
    if (!Platform.isAndroid) return status();
    final response = await _channel.invokeMapMethod<String, Object?>('stop');
    return _parse(response);
  }

  @override
  Future<void> openSystemWifiSettings() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openWifiSettings');
    }
  }

  HotspotState _parse(Map<String, Object?>? data) {
    if (data == null) {
      return const HotspotState(
        supported: false,
        active: false,
        reason: 'No hubo respuesta del adaptador Wi-Fi.',
      );
    }
    return HotspotState(
      supported: data['supported'] == true,
      active: data['active'] == true,
      ssid: data['ssid'] as String?,
      passphrase: data['passphrase'] as String?,
      reason: data['reason'] as String?,
    );
  }

  Future<ProcessResult> _nmcli(List<String> args) async =>
      Process.run('nmcli', args).timeout(const Duration(seconds: 20));

  Future<HotspotState> _linuxStatus() async {
    try {
      final active = await _nmcli([
        '-t',
        '-f',
        'NAME,TYPE,DEVICE',
        'connection',
        'show',
        '--active',
      ]);
      if (active.exitCode != 0) {
        return HotspotState(
          supported: false,
          active: false,
          reason: '${active.stderr}'.trim(),
        );
      }
      for (final row in '${active.stdout}'.split('\n')) {
        final fields = row.trim().split(':');
        if (fields.length >= 3 &&
            fields[0].startsWith('LANXIS-') &&
            fields[1] == '802-11-wireless') {
          return HotspotState(
            supported: true,
            active: true,
            ssid: fields[0],
            passphrase: fields[0] == _linuxProfile ? _linuxPassword : null,
          );
        }
      }
      final interface = await _linuxApInterface();
      return HotspotState(
        supported: interface != null,
        active: false,
        reason: interface == null
            ? 'NetworkManager no detecta una interfaz Wi-Fi compatible con AP.'
            : null,
      );
    } on ProcessException catch (e) {
      return HotspotState(
        supported: false,
        active: false,
        reason: 'NetworkManager/nmcli no está disponible: $e',
      );
    } catch (e) {
      return HotspotState(supported: false, active: false, reason: '$e');
    }
  }

  Future<String?> _linuxApInterface() async {
    final devices = await _nmcli([
      '-t',
      '-f',
      'DEVICE,TYPE',
      'device',
      'status',
    ]);
    if (devices.exitCode != 0) return null;
    for (final row in '${devices.stdout}'.split('\n')) {
      final fields = row.trim().split(':');
      if (fields.length < 2 || fields[1] != 'wifi') continue;
      final capabilities = await _nmcli([
        '-g',
        'WIFI-PROPERTIES.AP',
        'device',
        'show',
        fields[0],
      ]);
      if (capabilities.exitCode == 0 &&
          '${capabilities.stdout}'.trim().toLowerCase() == 'yes') {
        return fields[0];
      }
    }
    return null;
  }

  Future<HotspotState> _linuxStart() async {
    final existing = await _linuxStatus();
    if (existing.active || !existing.supported) return existing;
    final interface = await _linuxApInterface();
    if (interface == null) return existing;
    final random = Random.secure();
    final suffix = List.generate(
      3,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join().toUpperCase();
    final profile = 'LANXIS-$suffix';
    final password = List.generate(
      16,
      (_) =>
          'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'[random
              .nextInt(56)],
    ).join();
    final result = await _nmcli([
      '-w',
      '15',
      'device',
      'wifi',
      'hotspot',
      'ifname',
      interface,
      'con-name',
      profile,
      'ssid',
      profile,
      'password',
      password,
    ]);
    if (result.exitCode != 0) {
      return HotspotState(
        supported: true,
        active: false,
        reason: 'NetworkManager: ${result.stderr}'.trim(),
      );
    }
    _linuxProfile = profile;
    _linuxPassword = password;
    return HotspotState(
      supported: true,
      active: true,
      ssid: profile,
      passphrase: password,
    );
  }

  Future<HotspotState> _linuxStop() async {
    final existing = await _linuxStatus();
    if (!existing.active || existing.ssid == null) return existing;
    final profile = existing.ssid!;
    final result = await _nmcli(['connection', 'down', 'id', profile]);
    if (result.exitCode != 0) {
      return HotspotState(
        supported: true,
        active: true,
        ssid: profile,
        reason: 'NetworkManager: ${result.stderr}'.trim(),
      );
    }
    await _nmcli(['connection', 'delete', 'id', profile]);
    _linuxProfile = null;
    _linuxPassword = null;
    return _linuxStatus();
  }
}
