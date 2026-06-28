import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// FUNCTION 1b - Heart rate from a Bluetooth watch / chest strap.
//
// IMPORTANT: a watch only shows up here if it is BROADCASTING heart rate.
// Just being paired to the phone (Garmin Connect / Bluetooth settings) is NOT
// enough - on the Garmin Forerunner 55 turn on "Broadcast Heart Rate".
//
// (Bluetooth does NOT work on an emulator - use a real phone.)
class HeartRateMonitor {
  static final Guid _hrService = Guid('0000180d-0000-1000-8000-00805f9b34fb');
  static final Guid _hrData = Guid('00002a37-0000-1000-8000-00805f9b34fb');

  int? lastBpm; // latest heart rate, or null if not connected
  String? connectedName; // name of the connected device
  void Function(int bpm)? onHeartRate; // called when a new reading arrives

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _dataSubscription;

  // A readable name for a scan result (e.g. "Forerunner 55").
  static String nameOf(ScanResult result) {
    if (result.device.platformName.isNotEmpty) return result.device.platformName;
    if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    return 'Unknown device';
  }

  // Scan for every device that is broadcasting heart rate. Returns the list so
  // the run screen can let you pick the right one (e.g. the Garmin, not the
  // ASUS watch).
  Future<List<ScanResult>> scan(
      {Duration timeout = const Duration(seconds: 8)}) async {
    final found = <DeviceIdentifier, ScanResult>{};
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        found[r.device.remoteId] = r;
      }
    });
    await FlutterBluePlus.startScan(withServices: [_hrService], timeout: timeout);
    // Wait until the scan finishes.
    await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    await sub.cancel();
    return found.values.toList();
  }

  // Connect to a chosen device and start receiving its heart rate.
  // Logs each step so problems can be seen with: adb logcat -s flutter
  Future<bool> connect(BluetoothDevice device) async {
    await disconnect();
    _device = device;
    connectedName =
        device.platformName.isEmpty ? 'monitor' : device.platformName;

    try {
      await device.connect(timeout: const Duration(seconds: 15));
    } catch (e) {
      // connect() throws if it is already connected; that's fine, carry on.
      debugPrint('HR: connect() said: $e');
    }

    final services = await device.discoverServices();
    debugPrint('HR: found ${services.length} services on $connectedName: '
        '${services.map((s) => s.serviceUuid.str).toList()}');

    for (final service in services) {
      if (service.serviceUuid != _hrService) continue;
      for (final c in service.characteristics) {
        if (c.characteristicUuid != _hrData) continue;

        // Listen FIRST, then turn on notifications, so we don't miss the
        // first reading the watch sends.
        _dataSubscription = c.onValueReceived.listen((bytes) {
          final bpm = _readBpm(bytes);
          debugPrint('HR: data $bytes -> $bpm bpm');
          if (bpm != null) {
            lastBpm = bpm;
            onHeartRate?.call(bpm);
          }
        });
        await c.setNotifyValue(true);
        debugPrint('HR: notifications ON for heart-rate data. Waiting for beats...');
        return true;
      }
    }

    debugPrint('HR: heart-rate service/characteristic NOT found on this device. '
        'Make sure the watch is BROADCASTING heart rate, not just paired.');
    return false;
  }

  // Pull the heart-rate number out of the raw Bluetooth bytes.
  int? _readBpm(List<int> bytes) {
    if (bytes.length < 2) return null;
    final twoBytes = (bytes[0] & 0x01) == 1;
    if (twoBytes) {
      if (bytes.length < 3) return null;
      return bytes[1] + (bytes[2] << 8);
    }
    return bytes[1];
  }

  Future<void> disconnect() async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    await _device?.disconnect();
    _device = null;
  }
}
