import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/platform/wifi_qr.dart';

void main() {
  test('Wi-Fi QR escapes delimiters in real SSIDs and passwords', () {
    expect(
      wifiQrPayload(ssid: 'Lab; "A"', passphrase: r'pa:ss\word'),
      r'WIFI:T:WPA;S:Lab\; \"A\";P:pa\:ss\\word;;',
    );
  });
  test('Wi-Fi QR preserves WPA3 SAE and open network security', () {
    expect(
      wifiQrPayload(ssid: 'LANXIS', passphrase: 'secret123', security: 'SAE'),
      'WIFI:T:SAE;S:LANXIS;P:secret123;;',
    );
    expect(
      wifiQrPayload(ssid: 'LANXIS', security: 'nopass'),
      'WIFI:T:nopass;S:LANXIS;;',
    );
  });
}
