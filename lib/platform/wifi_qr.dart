/// Android Wi-Fi QR payload for WPA2, WPA3-SAE and open local hotspots.
String wifiQrPayload({
  required String ssid,
  String? passphrase,
  String security = 'WPA',
}) {
  if (ssid.isEmpty ||
      !{'WPA', 'SAE', 'nopass'}.contains(security) ||
      (security != 'nopass' && (passphrase == null || passphrase.isEmpty))) {
    throw ArgumentError('Se requieren SSID y clave para el QR de Wi-Fi');
  }
  String escape(String value) => value.replaceAllMapped(
    RegExp(r'[\\;,":]'),
    (match) => '\\${match.group(0)}',
  );
  return security == 'nopass'
      ? 'WIFI:T:nopass;S:${escape(ssid)};;'
      : 'WIFI:T:$security;S:${escape(ssid)};P:${escape(passphrase!)};;';
}
