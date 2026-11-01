import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const IPScannerApp());
}

class IPScannerApp extends StatelessWidget {
  const IPScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NetScanner Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        primaryColor: const Color(0xFF06B6D4),
      ),
      home: const ScannerHomePage(),
    );
  }
}

class DeviceResult {
  final String ip;
  final String ports;
  final String type;
  final String url;
  final int targetPort;

  DeviceResult({
    required this.ip,
    required this.ports,
    required this.type,
    required this.url,
    required this.targetPort,
  });
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  final TextEditingController _startIpController = TextEditingController(text: "192.168.1.1");
  final TextEditingController _endIpController = TextEditingController(text: "192.168.1.50");

  bool _isScanning = false;
  double _progress = 0.0;
  String _statusText = "Ready to scan";
  final List<DeviceResult> _results = [];
  final List<int> _probePorts = [80, 8080, 443, 8000, 37777, 554];

  int _ipToInt(String ip) {
    List<int> parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  String _intToIp(int intIp) {
    return "${(intIp >> 24) & 0xFF}.${(intIp >> 16) & 0xFF}.${(intIp >> 8) & 0xFF}.${intIp & 0xFF}";
  }

  Future<bool> _isPortOpen(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 700));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future> _detectDevice(String ip, List<int> openPorts) async {
    String type = "Generic Host";
    int? webPort;
    String proto = "http";

    if (openPorts.contains(37777)) {
      type = "Dahua DVR / NVR";
    }

    for (int p in [80, 8080, 443, 8000]) {
      if (openPorts.contains(p)) {
        webPort = p;
        proto = (p == 443) ? "https" : "http";
        try {
          final uri = Uri.parse("$proto://$ip:$p");
          final res = await http.get(uri).timeout(const Duration(milliseconds: 1200));
          String body = res.body.toLowerCase();
          String server = (res.headers['server'] ?? '').toLowerCase();

          if (server.contains("dahua") || body.contains("dahua") || body.contains("web_dvr")) {
            type = "Dahua DVR / IP Cam";
            break;
          } else if (["router", "openwrt", "tplink", "tp-link", "mercusys", "mikrotik", "d-link", "netis"]
              .any((k) => body.contains(k) || server.contains(k))) {
            type = "Network Router";
            break;
          }
        } catch (_) {}
      }
    }

    if (type == "Generic Host" && webPort != null) {
      type = "Web Device";
    }

    return {"type": type, "port": webPort ?? openPorts[0], "proto": proto};
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _results.clear();
      _progress = 0.0;
      _statusText = "Scanning network...";
    });

    try {
      int startInt = _ipToInt(_startIpController.text.trim());
      int endInt = _ipToInt(_endIpController.text.trim());

      if (startInt > endInt) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Start IP cannot be greater than End IP")),
        );
        setState(() => _isScanning = false);
        return;
      }

      int totalIps = endInt - startInt + 1;
      int completed = 0;

      for (int i = startInt; i <= endInt; i++) {
        if (!_isScanning) break;

        String currentIp = _intToIp(i);
        List<int> openPorts = [];

        for (int p in _probePorts) {
          if (await _isPortOpen(currentIp, p)) {
            openPorts.add(p);
          }
        }

        if (openPorts.isNotEmpty) {
          var details = await _detectDevice(currentIp, openPorts);
          _results.add(DeviceResult(
            ip: currentIp,
            ports: openPorts.join(', '),
            type: details['type'],
            url: "${details['proto']}://$currentIp:${details['port']}",
            targetPort: details['port'],
          ));
        }

        completed++;
        setState(() {
          _progress = completed / totalIps;
          _statusText = "Scanned $completed of $totalIps IPs (${(_progress * 100).toStringAsFixed(0)}%)";
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }

    setState(() {
      _isScanning = false;
      _statusText = "Scan Complete! Found ${_results.length} active devices.";
    });
  }

  void _openInBrowser(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Copied to clipboard: $text"), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("⚡ NetScanner Pro", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startIpController,
                            decoration: const InputDecoration(
                              labelText: "Start IP",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _endIpController,
                            decoration: const InputDecoration(
                              labelText: "End IP",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isScanning ? Colors.redAccent : Colors.tealAccent.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          if (_isScanning) {
                            setState(() => _isScanning = false);
                          } else {
                            _startScan();
                          }
                        },
                        icon: Icon(_isScanning ? Icons.stop : Icons.search, color: Colors.white),
                        label: Text(_isScanning ? "STOP SCAN" : "START SCAN",
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white12,
                  color: Colors.cyanAccent,
                  minHeight: 8,
                ),
                const SizedBox(height: 6),
                Text(_statusText, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _isScanning ? "Scanning..." : "No devices found yet.",
                        style: const TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final dev = _results[index];
                        final isDahua = dev.type.contains("Dahua");
                        final isRouter = dev.type.contains("Router");

                        return Card(
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: isDahua ? Colors.redAccent : (isRouter ? Colors.cyanAccent : Colors.transparent),
                              width: 1.2,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              isDahua ? Icons.videocam : (isRouter ? Icons.router : Icons.devices),
                              color: isDahua ? Colors.redAccent : (isRouter ? Colors.cyanAccent : Colors.white60),
                              size: 32,
                            ),
                            title: Row(
                              children: [
                                Text(dev.ip, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text("Port: ${dev.ports}", style: const TextStyle(fontSize: 11, color: Colors.yellowAccent)),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(dev.type, style: TextStyle(color: isDahua ? Colors.red.shade200 : Colors.tealAccent.shade100)),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy, color: Colors.white70),
                                  tooltip: "Copy IP:Port",
                                  onPressed: () => _copyToClipboard("${dev.ip}:${dev.targetPort}"),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.open_in_browser, color: Colors.lightBlueAccent),
                                  tooltip: "Open in Browser",
                                  onPressed: () => _openInBrowser(dev.url),
                                ),
                              ],
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
