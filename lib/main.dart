import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'welcome_page.dart';
import 'dart:async';
import 'services/mqtt_service.dart';
import 'package:pfe_bms_new/services/mqtt_service.dart';
import 'homepage.dart';




final mqttDataStreamController = StreamController<String>.broadcast();
final mqttService = MQTTService(
  broker: '192.168.56.1',
  port: 1883,
  clientId: 'flutter_client',
);


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Connect to MQTT broker before starting the app
  await mqttService.connect();
  mqttService.subscribe('bms/data');
  runApp(const MyApp());


}
Future<void> requestBluetoothPermissions() async {
  Map<Permission, PermissionStatus> statuses = await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ].request();

  if (statuses.values.any((status) => !status.isGranted)) {
    // Show a dialog or handle denied permissions
    print("Permissions not granted!");
  }
}
/*class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar:AppBar(
          title:

               Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("hi",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                    ),
                  ),

                  Text('yassine')
                ],

            ),

        ),
        ),
      
    ) ;
  }*/
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Homepage(
        dataStream: mqttService.messageStream, // Pass the live MQTT stream
        mqttService: mqttService,
      ),
    );
  }

}


