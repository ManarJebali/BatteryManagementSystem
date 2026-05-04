// bluetooth_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'homepage.dart';
import 'dart:async';
import 'package:pfe_bms_new/services/mqtt_service.dart';

// Use global MQTTService instance
import 'main.dart';

class BluetoothScannerScreen extends StatefulWidget {
  const BluetoothScannerScreen({super.key});

  @override
  State<BluetoothScannerScreen> createState() => _BluetoothScannerScreenState();
}

class _BluetoothScannerScreenState extends State<BluetoothScannerScreen> {
  final List<ScanResult> _devices = [];
  bool _isScanning = false;
  bool _hasScanListener = false;
  final StreamController<String> _dataStreamController = StreamController<String>.broadcast();
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;

  @override
  void initState() {
    super.initState();
    _requestPermissions().then((_) => _startScan());
    _listenToScanResults();
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (!mounted) return;

    if (statuses.values.any((status) => status.isDenied)) {
      if (statuses.values.any((status) => status.isPermanentlyDenied)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Permissions permanently denied. Open settings to enable them.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: openAppSettings,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth and location permissions are required.')),
        );
      }
    }
  }

  void _listenToScanResults() {
    if (_hasScanListener) return;
    _hasScanListener = true;

    FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        _devices
          ..clear()
          ..addAll(results.where((r) => r.device.platformName.isNotEmpty));
        _isScanning = false;
      });
    });
  }

  Future<void> _startScan() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enable Bluetooth.'),
          action: SnackBarAction(
            label: 'Enable',
            onPressed: FlutterBluePlus.turnOn,
          ),
        ),
      );
      return;
    }

    setState(() => _isScanning = true);
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();

    try {
      await device.connect(autoConnect: false);
      _connectedDevice = device;
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);
            characteristic.onValueReceived.listen((value) {
              final message = String.fromCharCodes(value);
              _dataStreamController.sink.add(message);
            });
          }
          if (characteristic.properties.write) {
            _writeCharacteristic = characteristic;
          }
        }
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to ${device.platformName}'), duration: Duration(seconds: 3)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }

  Future<void> _disconnectFromDevice() async {
    try {
      await _connectedDevice?.disconnect();
      _connectedDevice = null;
      _writeCharacteristic = null;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected'), duration: Duration(seconds: 3)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error disconnecting: $e')),
      );
    }
  }

  @override
  void dispose() {
    _dataStreamController.close();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Bluetooth Scanner",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.amber,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isScanning
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {

                final result = _devices[index];
                final isConnected = _connectedDevice?.remoteId == result.device.remoteId;
                return ListTile(
                  tileColor: isConnected ? Colors.green[100] : null,
                  title: Text(result.device.platformName),
                  subtitle: Text(result.device.remoteId.str),
                  onTap: () => _connectToDevice(result.device),
                );
              },
            ),
          ),
          if (_connectedDevice != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Homepage(
                            dataStream: _dataStreamController.stream,
                            //writeCharacteristic: _writeCharacteristic,
                            mqttService: mqttService,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.home),
                    label: const Text("START"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _disconnectFromDevice,
                    icon: const Icon(Icons.cancel),
                    label: const Text("Disconnect"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startScan,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
