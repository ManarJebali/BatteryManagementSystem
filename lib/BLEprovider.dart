import 'package:flutter/material.dart';

class BluetoothDataProvider extends ChangeNotifier {
  double c1 = 0;
  double c2 = 0;
  double c3 = 0;
  double c4 = 0;
  double temperature = 0;
  double voltage = 0;
  double current = 0;
  double power = 0;

  void updateFromStream(String data) {
    final parts = data.split(',');

    for (var part in parts) {
      final kv = part.split(':');
      if (kv.length == 2) {
        final key = kv[0].trim().toUpperCase();
        final value = double.tryParse(kv[1].trim()) ?? 0;

        switch (key) {
          case 'C1': c1 = value; break;
          case 'C2': c2 = value; break;
          case 'C3': c3 = value; break;
          case 'C4': c4 = value; break;
          case 'TEMP': temperature = value; break;
          case 'VOLTAGE': voltage = value; break;
          case 'CURRENT': current = value; break;
          case 'POWER': power = value; break;
        }
      }
    }

    notifyListeners(); // Notifies the UI
  }
}
