import 'package:flutter/material.dart';
import 'bluetooth_page.dart';
import 'homepage.dart';
import 'main.dart';

class welcome_page extends StatefulWidget {
  const welcome_page({super.key});

  @override
  State<welcome_page> createState() => _welcome_pageState();
}

class _welcome_pageState extends State<welcome_page> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(child: Text("ASSAD BMS",
            style: TextStyle(
                fontSize: 30,
                color: Colors.white

            )
        )
        ),
        backgroundColor: Colors.amber,
      ),
      body:  Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center ,
          children: [
            Image.asset('assets/images/logo.png',
              width: 150,
              height: 150,),
            const SizedBox(height: 50),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 4,
                child: ListTile(
                  leading: const Icon(Icons.bluetooth, color: Colors.black),
                  title: const Text("Local monitoring"),
                  subtitle: const Text("bluetooth device"),
                  trailing: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        //builder: (context) => BluetoothScannerScreen(),
                        builder: (context) => Homepage(dataStream: mqttService.messageStream,
                        mqttService: mqttService,),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 4,
                child: ListTile(
                  leading: const Icon(Icons.wifi, color: Colors.black),
                  title: const Text("Remote monitoring"),
                  subtitle: const Text("Wifi or 4G devices"),
                  trailing: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                  onTap: () {

                  },
                ),
              ),
            ),


          ],
        ),
      ),
    );
  }
}