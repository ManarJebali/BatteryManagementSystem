// control.dart
import 'package:flutter/material.dart';
//import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'homepage.dart';
import 'main.dart';
import 'package:pfe_bms_new/services/mqtt_service.dart';
import 'package:typed_data/typed_buffers.dart';
import 'dart:async';




class Control extends StatefulWidget {
  final Stream<String> dataStream;
  //final BluetoothCharacteristic? writeCharacteristic;
  final MQTTService mqttService;

  const Control({
    super.key,
    required this.dataStream,
   // required this.writeCharacteristic,
    required this.mqttService,

  });

  @override
  State<Control> createState() => _ControlState();
}

class _ControlState extends State<Control> {
  final Map<String, TextEditingController> controllers = {
    "Single cell volt-high (3.65V)": TextEditingController(),
    "Single cell volt-low (2.00V)": TextEditingController(),
    "Sum volt high protect (69.30V)": TextEditingController(),
    "Sum volt low protect (38.00V)": TextEditingController(),
    "Differential pressure alarm (0.80V)": TextEditingController(),
    "Chg overcurrent protect (50.0A)": TextEditingController(),
    "Dischg overcurrent protect (140.0A)": TextEditingController(),
    "Rated capacity (50.0AH)": TextEditingController(),
    "Cell reference volt (3.20V)": TextEditingController(),
    "SOC set (100.0%)": TextEditingController(),
    "Balanced open start volt (3.40V)": TextEditingController(),
    "Balanced open diff volt (0.02V)": TextEditingController(),
    "Chg high temp protect (55°C)": TextEditingController(),
    "Chg low temp protect (0°C)": TextEditingController(),
    "Dischg high temp protect (55°C)": TextEditingController(),
    "Dischg low temp protect (0°C)": TextEditingController(),
  };

  /*void _sendValue(String key, String value) async {
    if (widget.writeCharacteristic == null) return;

    final command = "$key:$value\n";
    try {
      await widget.writeCharacteristic!.write(command.codeUnits);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent: $command')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
    }
  }*/

//  NEW: variables to store live MQTT data
  StreamSubscription<String>? _subscription;
  String latestData = "";

  @override
  void initState() {
    super.initState();
    //  NEW: listen to live MQTT data
    _subscription = widget.dataStream.listen((data) {
      setState(() {
        latestData = data;
      });
    });
  }

  //  NEW: cleanup
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _sendValue(String key, String value) {
    final message = "$key:$value";
    final buffer = Uint8Buffer();
    buffer.addAll(message.codeUnits);

    mqttService.publish("bms/control", buffer);

    print("MQTT → Publish: $message");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sent over MQTT: $message')),
    );
  }


  DataRow _buildRow(String parameter, TextEditingController controller) {
    return DataRow(
      cells: [
        DataCell(Text(parameter)),
        DataCell(
          TextField(
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: 'Enter value',
              border: InputBorder.none,
            ),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: () {
              _sendValue(parameter.split('(')[0].trim(), controller.text.trim());
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Control Panel", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.amber,
      ),
      /*body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Parameter', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Value', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: controllers.entries
              .map((entry) => _buildRow(entry.key, entry.value))
              .toList(),
        ),
      ),*/
      body: StreamBuilder<String>(   // NEW: listen to the broadcast MQTT stream
        stream: widget.dataStream,  // NEW
        builder: (context, snapshot) { // NEW
          final latestData = snapshot.data ?? ""; // NEW

          return Column(
            children: [
              if (latestData.isNotEmpty)        // NEW
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    "Live Data: $latestData",  // NEW
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.green), // NEW
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Parameter', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Value', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: controllers.entries
                        .map((entry) => _buildRow(entry.key, entry.value))
                        .toList(),
                  ),
                ),
              ),
            ],
          );
        },
      ),

      bottomNavigationBar: BottomAppBar(
        color: Colors.amber,
        shape: const CircularNotchedRectangle(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.home, color: Colors.white, size: 30),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    /*builder: (context) => Homepage(
                      dataStream: widget.dataStream,
                      //writeCharacteristic: widget.writeCharacteristic,),*/
                    builder: (context) => Control(dataStream: widget.dataStream,
                      mqttService: widget.mqttService, ),
                    
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 30),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
