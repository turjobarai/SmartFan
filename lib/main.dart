import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';




void main() {
  runApp(const SmartFanApp());
}

/// 🔹 Log model & manager
class FanLog {
  final DateTime dateTime;
  final String action;
  final int speed;
  final String timerUsed;

  FanLog({
    required this.dateTime,
    required this.action,
    required this.speed,
    required this.timerUsed,
  });

  Map<String, dynamic> toJson() => {
    'dateTime': dateTime.toIso8601String(),
    'action': action,
    'speed': speed,
    'timerUsed': timerUsed,
  };

  factory FanLog.fromJson(Map<String, dynamic> json) => FanLog(
    dateTime: DateTime.parse(json['dateTime']),
    action: json['action'],
    speed: json['speed'],
    timerUsed: json['timerUsed'],
  );
}

class LogManager {
  static final LogManager _instance = LogManager._internal();
  factory LogManager() => _instance;
  LogManager._internal();

  final List<FanLog> _logs = [];

  List<FanLog> get logs => List.unmodifiable(_logs);

  Future<void> loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString('fanLogs');
    if (stored != null) {
      final List<dynamic> jsonList = jsonDecode(stored);
      _logs.clear();
      _logs.addAll(jsonList.map((e) => FanLog.fromJson(e)));
    }
  }

  Future<void> _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _logs.map((e) => e.toJson()).toList();
    await prefs.setString('fanLogs', jsonEncode(jsonList));
  }

  Future<void> addLog(FanLog log) async {
    _logs.insert(0, log);
    await _saveLogs();
  }

  Future<void> clearLogs() async {
    _logs.clear();
    await _saveLogs();
  }
}

/// 🔹 App Start
class SmartFanApp extends StatelessWidget {
  const SmartFanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Fan Controller',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashScreenWithSlider(),
    );
  }
}

/// 🔹 Splash Screen
class SplashScreenWithSlider extends StatefulWidget {
  const SplashScreenWithSlider({super.key});

  @override
  State<SplashScreenWithSlider> createState() =>
      _SplashScreenWithSliderState();
}

class _SplashScreenWithSliderState extends State<SplashScreenWithSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreenTabs()),
        );
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              "assets/icon.png",
              width: 100,
              height: 100,
            ),
            const SizedBox(height: 20),
            Container(
              width: 180,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(5),
              ),
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _animation.value,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🔹 Main Tabs
class HomeScreenTabs extends StatelessWidget {
  HomeScreenTabs({super.key});

  final GlobalKey<_HomePageState> homeKey = GlobalKey<_HomePageState>();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("SmartFan"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Home"),
              Tab(text: "Timer"),
              Tab(text: "Settings"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            HomePage(key: homeKey),
            TimerPage(homeKey: homeKey),
            const SettingsPage(),
          ],
        ),
      ),
    );
  }
}

/// 🔹 Home Page
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  List<BluetoothDevice> devices = [];
  BluetoothConnection? connection;
  BluetoothDevice? connectedDevice;

  ValueNotifier<bool> deviceConnectedNotifier = ValueNotifier(false);

  bool fanState = false;
  int fanSpeed = 50;
  int lastSavedSpeed = 50;

  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
    _loadSavedState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      fanSpeed = prefs.getInt('fanSpeed') ?? 50;
      lastSavedSpeed = fanSpeed;
      fanState = prefs.getBool('fanState') ?? false;
    });
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fanSpeed', fanSpeed);
    await prefs.setBool('fanState', fanState);
  }

  Future<void> _loadPairedDevices() async {
    List<BluetoothDevice> bondedDevices = await _bluetooth.getBondedDevices();
    setState(() {
      devices = bondedDevices;
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    try {
      final conn = await BluetoothConnection.toAddress(device.address);
      setState(() {
        connection = conn;
        connectedDevice = device;
        deviceConnectedNotifier.value = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${device.name ?? device.address} connected"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      connection!.input!.listen(null).onDone(() {
        setState(() {
          connectedDevice = null;
          connection = null;
          deviceConnectedNotifier.value = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Device disconnected"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      });
    } catch (e) {
      deviceConnectedNotifier.value = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Connection failed: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _sendPower(int power) {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(
        Uint8List.fromList((power.toString() + "\n").codeUnits),
      );
    }
  }

  void _setFanSpeed(int value, {bool fromSlider = false}) {
    setState(() {
      fanSpeed = value;
      fanState = fanSpeed > 0;
      lastSavedSpeed = fanSpeed;
    });
    _sendPower(fanSpeed);
    _saveState();

    if (fromSlider) {
      LogManager().addLog(FanLog(
        dateTime: DateTime.now(),
        action: fanState ? "ON" : "OFF",
        speed: fanSpeed,
        timerUsed: "00:00:00",
      ));
    }
  }

  Widget _fanControl() {
    if (connectedDevice == null) {
      return const Center(child: Text("Connect a device first"));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () {
            setState(() {
              if (fanState) {
                fanState = false;
                fanSpeed = 0;
                _sendPower(0);
                LogManager().addLog(FanLog(
                  dateTime: DateTime.now(),
                  action: "OFF",
                  speed: fanSpeed,
                  timerUsed: "00:00:00",
                ));
              } else {
                fanState = true;
                fanSpeed = lastSavedSpeed;
                _sendPower(fanSpeed);
                LogManager().addLog(FanLog(
                  dateTime: DateTime.now(),
                  action: "ON",
                  speed: fanSpeed,
                  timerUsed: "00:00:00",
                ));
              }
              _saveState();
            });
          },
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (_, child) {
                  double turns = fanState && fanSpeed > 0
                      ? _controller.value * (fanSpeed / 20)
                      : 0;
                  return Transform.rotate(
                    angle: turns * 2 * math.pi,
                    child: Image.asset(
                      "assets/fan.png",
                      width: 60,
                      height: 60,
                      color: fanState ? Colors.blue : Colors.grey,
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Text(
                "$fanSpeed%",
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: (fanSpeed / 100) * MediaQuery.of(context).size.width,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  double newVal = ((details.localPosition.dx /
                      MediaQuery.of(context).size.width) *
                      100)
                      .clamp(0, 100);
                  _setFanSpeed(newVal.toInt(), fromSlider: true);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _presetButton("Off", 0),
            _presetButton("Low", 25),
            _presetButton("Medium", 50),
            _presetButton("High", 75),
            _presetButton("Max", 100),
          ],
        ),
      ],
    );
  }

  Widget _presetButton(String label, int value) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: fanSpeed == value ? Colors.blue : Colors.grey[300],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        minimumSize: const Size(20, 20),
      ),
      onPressed: () {
        _setFanSpeed(value, fromSlider: true);
      },
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: _fanControl(),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.devices),
        onPressed: () async {
          BluetoothDevice? device = await showDialog<BluetoothDevice>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text("Select Device"),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView(
                    shrinkWrap: true,
                    children: devices
                        .map(
                          (device) => ListTile(
                        title: Text(device.name ?? device.address),
                        onTap: () {
                          Navigator.pop(context, device);
                        },
                      ),
                    )
                        .toList(),
                  ),
                ),
              );
            },
          );

          if (device != null) {
            _connect(device);
          }
        },
      ),
    );
  }
}

/// 🔹 Timer Page (Updated Dynamic Minutes)
/// 🔹 Timer Page (Single Card)
class TimerPage extends StatefulWidget {
  final GlobalKey<_HomePageState> homeKey;
  const TimerPage({super.key, required this.homeKey});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage>
    with AutomaticKeepAliveClientMixin {
  int selectedHour = 0;
  int selectedMinute = 1;
  Duration remaining = Duration.zero;
  Timer? countdownTimer;
  bool isRunning = false;

  void startTimer() {
    setState(() {
      remaining = Duration(hours: selectedHour, minutes: selectedMinute);
      isRunning = true;
    });

    countdownTimer?.cancel();

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remaining.inSeconds <= 0) {
        timer.cancel();
        setState(() {
          remaining = Duration.zero;
          isRunning = false;
        });

        final homeState = widget.homeKey.currentState;
        if (homeState != null) {
          homeState.setState(() {
            homeState.fanState = false;
            homeState.fanSpeed = 0;
            homeState._sendPower(0);
          });
          LogManager().addLog(FanLog(
            dateTime: DateTime.now(),
            action: "OFF",
            speed: 0,
            timerUsed:
            "${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}:00",
          ));
        }
      } else {
        setState(() {
          remaining = remaining - const Duration(seconds: 1);
        });
      }
    });
  }

  void resetTimer() {
    countdownTimer?.cancel();
    setState(() {
      remaining = Duration.zero;
      isRunning = false;
      selectedHour = 0;
      selectedMinute = 1;
    });
  }

  void addOneMinute() {
    if (isRunning) {
      setState(() {
        remaining += const Duration(minutes: 1);
      });
    }
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes % 60)}:${twoDigits(d.inSeconds % 60)}";
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final homeState = widget.homeKey.currentState;
    if (homeState == null) return const SizedBox();

    return ValueListenableBuilder<bool>(
      valueListenable: homeState.deviceConnectedNotifier,
      builder: (context, deviceConnected, _) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            elevation: 3,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  /// ⏰ Timer selectors
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: selectedHour,
                          decoration: const InputDecoration(
                            labelText: "Hour",
                            border: OutlineInputBorder(),
                          ),
                          items: List.generate(
                              25,
                                  (index) =>
                                  DropdownMenuItem(value: index, child: Text("$index hr"))),
                          onChanged: (!deviceConnected || isRunning)
                              ? null
                              : (value) {
                            setState(() {
                              selectedHour = value ?? 0;
                              if (selectedHour == 0 && selectedMinute == 0) {
                                selectedMinute = 1;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: selectedMinute,
                          decoration: const InputDecoration(
                            labelText: "Minute",
                            border: OutlineInputBorder(),
                          ),
                          items: List.generate(
                              selectedHour == 0 ? 59 : 60,
                                  (index) => DropdownMenuItem(
                                value: selectedHour == 0 ? index + 1 : index,
                                child: Text(selectedHour == 0
                                    ? "${index + 1} min"
                                    : "$index min"),
                              )),
                          onChanged: (!deviceConnected || isRunning)
                              ? null
                              : (value) {
                            setState(() {
                              selectedMinute =
                                  value ?? (selectedHour == 0 ? 1 : 0);
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  /// ▶️ Start/Reset + Countdown
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: deviceConnected
                              ? () {
                            if (!isRunning) {
                              startTimer();
                            } else {
                              resetTimer();
                            }
                          }
                              : null,
                          icon: Icon(
                              isRunning ? Icons.refresh : Icons.play_arrow),
                          label:
                          Text(isRunning ? "Reset Timer" : "Start Timer"),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (isRunning)
                        FilledButton.tonal(
                          onPressed: addOneMinute,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(90, 50),
                          ),
                          child: const Text("+1 Min"),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Text(
                    formatDuration(remaining),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}





/// 🔹 Settings Page
/// 🔹 Updated SettingsPage with Feedback
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _sendFeedback(BuildContext context) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'turjobarai4@gmail.com',
      queryParameters: {'subject': 'SmartFan App Feedback'},
    );
    if (!await launchUrl(emailUri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open email client")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          elevation: 3,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SystemLogsPage()));
            },
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: const [
                  Icon(Icons.list, color: Colors.blue),
                  SizedBox(width: 10),
                  Text("System Logs",
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        Card(
          elevation: 3,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const AboutPage()));
            },
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: const [
                  Icon(Icons.info, color: Colors.green),
                  SizedBox(width: 10),
                  Text("About",
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        Card(
          elevation: 3,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _sendFeedback(context),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: const [
                  Icon(Icons.feedback, color: Colors.redAccent),
                  SizedBox(width: 10),
                  Text("Send Feedback",
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}


/// 🔹 System Logs Page
class SystemLogsPage extends StatefulWidget {
  const SystemLogsPage({super.key});

  @override
  State<SystemLogsPage> createState() => _SystemLogsPageState();
}

class _SystemLogsPageState extends State<SystemLogsPage> {
  final LogManager logManager = LogManager();

  @override
  void initState() {
    super.initState();
    logManager.loadLogs().then((_) => setState(() {}));
  }

  void _clearLogs() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text("Clear Logs"),
            content: const Text("Do you want to clear all logs?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel")),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("OK")),
            ],
          );
        });

    if (confirmed == true) {
      await logManager.clearLogs();
      setState(() {});
    }
  }

  Widget _buildLogRow(FanLog log) {
    int hour12 = log.dateTime.hour % 12;
    if (hour12 == 0) hour12 = 12;
    String ampm = log.dateTime.hour >= 12 ? "PM" : "AM";

    String formattedTime =
        "${hour12.toString().padLeft(2, '0')}:${log.dateTime.minute.toString().padLeft(2, '0')} $ampm";

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
                "${log.dateTime.day}-${log.dateTime.month}-${log.dateTime.year}\n$formattedTime"),
          ),
          Expanded(
            flex: 1,
            child: Text(
              log.action,
              style: TextStyle(
                  color: log.action == "ON" ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text("${log.speed}%"),
          ),
          Expanded(
            flex: 2,
            child: Text(log.timerUsed),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = logManager.logs;

    return Scaffold(
      appBar: AppBar(
        title: const Text("System Logs"),
        actions: [
          IconButton(
              onPressed: _clearLogs,
              icon: const Icon(Icons.delete, color: Colors.black))
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text("No logs yet"))
          : ListView(
        padding: const EdgeInsets.all(10),
        children: logs.map(_buildLogRow).toList(),
      ),
    );
  }
}





/// 🔹 About Page (Final Version with Grid Contact Links)
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("About"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // App info
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 6,
              color: Colors.white70,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.info_outline, color: Colors.blue, size: 28),
                        SizedBox(width: 10),
                        Text(
                          "App Info",
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Text("Version: 1.0.0",
                        style: TextStyle(fontSize: 16)),
                    const Text("Release Date: Sep 2025",
                        style: TextStyle(fontSize: 16)),
                    const Text("Developer: Turjo Barai",
                        style: TextStyle(fontSize: 16)),
                    const Text("App Name: SmartFan",
                        style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),


            const SizedBox(height: 20),



            // Contact Card inside AboutPage
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 5,
              color: Colors.white70
              ,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    const Text(
                      "You will find me here",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 15),
                    GridView.count(
                      crossAxisCount: 3, // 3 columns
                      shrinkWrap: true,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      childAspectRatio: 1,
                      physics: const NeverScrollableScrollPhysics(),
                      children: const [
                        ContactItem(
                          label: "Email",
                          url: "mailto:turjobarai4@gmail.com",
                          icon: FontAwesomeIcons.envelope,
                        ),
                        ContactItem(
                          label: "Website",
                          url: "https://turjobe.netlify.app",
                          icon: Icons.language,
                        ),
                        ContactItem(
                          label: "Telegram",
                          url: "https://t.me/turjobe",
                          icon: FontAwesomeIcons.telegram,
                        ),
                        ContactItem(
                          label: "GitHub",
                          url: "https://github.com/turjobarai",
                          icon: FontAwesomeIcons.github,
                        ),
                        ContactItem(
                          label: "Facebook",
                          url: "https://facebook.com/turjobarai",
                          icon: FontAwesomeIcons.facebook,
                        ),
                        ContactItem(
                          label: "YouTube",
                          url: "https://youtube.com/@turjobarai",
                          icon: FontAwesomeIcons.youtube,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Thanks
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 6,
              color: Colors.white70,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [

                      ],
                    ),
                    const Text(
                      "Thank you for using SmartFan App!",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const Text(
                      "We hope it makes your life easier.",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}

/// 🔹 Contact Item Widget
class ContactItem extends StatelessWidget {
  final String label;
  final String url;
  final IconData icon;

  const ContactItem(
      {super.key, required this.label, required this.url, required this.icon});

  void _launchURL() async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint("Could not launch $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _launchURL,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: Colors.blue),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.blue),
          ),
        ],
      ),
    );
  }
}
