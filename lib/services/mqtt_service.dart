import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:typed_data';
import 'package:typed_data/typed_data.dart';
import 'package:typed_data/typed_buffers.dart';

import '../main.dart';


class MQTTService {
  final String broker;         // e.g., the private server IP
  final int port;              // usually 1883 for MQTT
  final String clientId;       // unique client id
  final String username;       // if your broker requires authentication
  final String password;       // if your broker requires authentication

  late MqttServerClient _client;
  final StreamController<String> _messageStreamController = StreamController.broadcast();

  Stream<String> get messages => _messageStreamController.stream;

  MQTTService({
    required this.broker,
    required this.port,
    required this.clientId,
    this.username = '',
    this.password = '',
  }) {
    _client = MqttServerClient(broker, clientId);
    _client.port = port;
    _client.logging(on: false);
    _client.keepAlivePeriod = 20;
    _client.onDisconnected = _onDisconnected;
    _client.onConnected = _onConnected;
    _client.onSubscribed = _onSubscribed;
  }

  Stream<String> get messageStream => _messageStreamController .stream;

  // connects to the broker with optional authentication.
  Future<bool> connect() async {
    try {
      final connMess = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      _client.connectionMessage = connMess;

      if (username.isNotEmpty) {
        _client.connectionMessage = MqttConnectMessage()
            .authenticateAs(username, password)
            .withClientIdentifier(clientId)
            .startClean();
      }

      await _client.connect(username, password);
    } catch (e) {
      print('MQTT client connection failed - $e');
      _client.disconnect();
      return false;
    }

    // Listen to messages from subscribed topics
    _client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final recMess = c![0].payload as MqttPublishMessage;
      final pt =
      MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      _messageStreamController.add(pt);
    });

    return _client.connectionStatus!.state == MqttConnectionState.connected;
  }

  MqttClient get client => _client; // Client getter


  //subscribes to a topic to receive messages.
  void subscribe(String topic) {
    if (_client.connectionStatus!.state == MqttConnectionState.connected) {
      print('Subscribing to $topic');
      _client.subscribe(topic, MqttQos.atMostOnce);
    }
  }

  //publishes a message to a topic.
  void publish(String topic, Uint8Buffer message) {
    _client.publishMessage(topic, MqttQos.atMostOnce, message);
  }


  void publishCommand(MQTTService mqttService, String command, double value) {
    // Format command string
    String message = "$command:$value";

    // Convert string to Uint8Buffer
    final buffer = Uint8Buffer();
    buffer.addAll(message.codeUnits);

    // Publish to the ESP32 control topic
    mqttService.publish('bms/control', buffer);

    print('Published command to ESP32: $message');
  }




  void disconnect() {
    _client.disconnect();
  }

  void _onConnected() {
    print('MQTT client connected');
  }

  void _onDisconnected() {
    print('MQTT client disconnected');
  }

  void _onSubscribed(String topic) {
    print('Subscribed to $topic');
  }
}
