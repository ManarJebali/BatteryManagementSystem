import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:pfe_bms_new/services/mqtt_service.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'control.dart';

class Homepage extends StatefulWidget {
  final Stream<String> dataStream;
  final MQTTService mqttService;

  const Homepage({
    Key? key,
    required this.dataStream,
    required this.mqttService,
  }) : super(key: key);

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  double percentage = 0;
  double c1 = 0;
  double c2 = 0;
  double c3 = 0;
  double c4 = 0;
  double temperature = 0;
  var T = Colors.amber;
  double voltage = 0;
  double current = 0;
  double power = 0;

  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.dataStream.listen((data) {
      _parseData(data);
    });

    // NEW: Subscribe to MQTT topic directly
    widget.mqttService.subscribe('bms/output'); // NEW

    // NEW: Listen for MQTT updates
    widget.mqttService.client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final recMess = c[0].payload as MqttPublishMessage;
      final message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      _parseData(message); // reuse your parsing logic
    });
  }

  void _parseData(String data) {
    final parts = data.split(',');

    for (var part in parts) {
      final kv = part.split(':');
      if (kv.length == 2) {
        final key = kv[0].trim().toUpperCase();
        final value = double.tryParse(kv[1].trim()) ?? 0;
        setState(() {
          switch (key) {
            case 'C1':
              c1 = value;
              break;
            case 'C2':
              c2 = value;
              break;
            case 'C3':
              c3 = value;
              break;
            case 'C4':
              c4 = value;
              break;
            case 'PACK':
              voltage = value;
              break;
            case 'TEMP':
              temperature = value;
              if (temperature < 47) {
                T = Colors.green;
              } else if (temperature > 60) {
                T = Colors.red;
              } else {
                T = Colors.amber;
              }
              break;
            case 'COURANT':
              current = value;
              break;
            case "SOC":
              percentage = value;
              break;
          }
        });
      }
    }
  }

@override
void dispose() {
  // NEW: Cancel subscription
  _subscription?.cancel(); // NEW
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.amber),
      body: ListView(
        children: [
          Column(
            children: [
              Container(
                color: Colors.black54,
                child: SfRadialGauge(
                  axes: [
                    RadialAxis(
                      maximum: 100,
                      interval: 25,
                      showTicks: true,
                      minorTicksPerInterval: 5,
                      majorTickStyle: const MajorTickStyle(length: 20, thickness: 3, color: Colors.black),
                      minorTickStyle: const MinorTickStyle(length: 10, thickness: 1, color: Colors.black),
                      ranges: [
                        GaugeRange(startValue: 0, endValue: 25, color: Colors.red),
                        GaugeRange(startValue: 25, endValue: 50, color: Colors.yellow),
                        GaugeRange(startValue: 50, endValue: 75, color: Colors.green.shade400),
                        GaugeRange(startValue: 75, endValue: 100, color: Colors.green),
                      ],
                      pointers: [
                        NeedlePointer(
                          value: percentage,
                          needleColor: Colors.red,
                          needleEndWidth: 15,
                          needleStartWidth: 1,
                          enableAnimation: true,
                        )
                      ],
                      annotations: [
                        GaugeAnnotation(
                          widget: Column(
                            children: [
                              Stack(
                                alignment: const Alignment(0, 0.2),
                                children: [
                                  Image.asset("assets/images/shape.png", height: 140),
                                  Text('%${percentage.toStringAsFixed(1)}',
                                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Spacer(),
                                  Text("VOLTAGE : $voltage V",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                                  const Spacer(),
                                  Text("CURRENT : $current A",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                                  const Spacer(),
                                  Text("CAPACITY : $power Ah",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                                  const Spacer(),
                                ],
                              )
                            ],
                          ),
                          angle: 90,
                          positionFactor: 1.1,
                        ),
                      ],
                    )
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBattery(c1),
                  _buildBattery(c2),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBattery(c3),
                  _buildBattery(c4),
                ],
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset("assets/images/termo.png", height: 150),
                  Text("$temperature",
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: T)),
                ],
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.amber,
        shape: const CircularNotchedRectangle(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.home, color: Colors.white, size: 30),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 30),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Control(
                      dataStream: widget.dataStream,
                      mqttService: widget.mqttService,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBattery(double value) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Image.asset("assets/images/batterie.png", height: 100),
        Text("${value.toStringAsFixed(3)}v"),
      ],
    );
  }
}
