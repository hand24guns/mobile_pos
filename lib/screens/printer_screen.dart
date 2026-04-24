import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/printer_helper.dart';
import 'package:permission_handler/permission_handler.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  List<BluetoothInfo> _devices = [];
  String? _connectedMac;
  String? _connectedName;
  bool _isScanning = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _connectedMac = prefs.getString('printer_mac');
      _connectedName = prefs.getString('printer_name');
    });
  }

  Future<void> _scanDevices() async {
    setState(() => _isScanning = true);
    try {
      // Request permissions dulu
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.locationWhenInUse,
      ].request();

      bool allGranted = statuses.values.every((s) => s.isGranted);

      if (!allGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Permission Bluetooth belum diizinkan. Buka Settings → Apps → Permission'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isScanning = false);
        return;
      }

      final devices = await PrinterHelper.scanDevices();
      setState(() => _devices = devices);

      if (_devices.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Tidak ada perangkat Bluetooth yang paired')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scan: $e')),
        );
      }
    }
    setState(() => _isScanning = false);
  }

  Future<void> _connectPrinter(BluetoothInfo device) async {
    setState(() => _isConnecting = true);
    try {
      final result = await PrinterHelper.connect(device.macAdress);
      if (result) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('printer_mac', device.macAdress);
        await prefs.setString('printer_name', device.name);
        setState(() {
          _connectedMac = device.macAdress;
          _connectedName = device.name;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Terhubung ke ${device.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal terhubung ke printer'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
    setState(() => _isConnecting = false);
  }

  Future<void> _disconnect() async {
    await PrinterHelper.disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('printer_mac');
    await prefs.remove('printer_name');
    setState(() {
      _connectedMac = null;
      _connectedName = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printer disconnected')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D273B),
        title: const Text('Pengaturan Printer',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status printer aktif
            if (_connectedName != null)
              Card(
                color: Colors.green.shade50,
                child: ListTile(
                  leading: const Icon(Icons.print, color: Colors.green),
                  title: Text(_connectedName!,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_connectedMac ?? ''),
                  trailing: TextButton(
                    onPressed: _disconnect,
                    child: const Text('Disconnect',
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
              ),
            if (_connectedName == null)
              const Card(
                color: Color(0xFFFFF3E0),
                child: ListTile(
                  leading: Icon(Icons.print_disabled, color: Colors.orange),
                  title: Text('Belum ada printer terhubung'),
                ),
              ),
            const SizedBox(height: 16),
            // Tombol scan
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _scanDevices,
                icon: _isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bluetooth_searching),
                label: Text(
                    _isScanning ? 'Scanning...' : 'Scan Perangkat Bluetooth'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D273B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // List device
            if (_devices.isNotEmpty) ...[
              const Text('Perangkat Tersedia:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (_, i) {
                    final device = _devices[i];
                    final isActive = device.macAdress == _connectedMac;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.bluetooth,
                          color: isActive ? Colors.green : Colors.blue,
                        ),
                        title: Text(device.name),
                        subtitle: Text(device.macAdress),
                        trailing: isActive
                            ? const Chip(
                                label: Text('Connected'),
                                backgroundColor: Colors.green,
                                labelStyle: TextStyle(color: Colors.white),
                              )
                            : ElevatedButton(
                                onPressed: _isConnecting
                                    ? null
                                    : () => _connectPrinter(device),
                                child: const Text('Connect'),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (_devices.isEmpty && !_isScanning)
              const Center(
                child: Text('Tap "Scan" untuk mencari printer',
                    style: TextStyle(color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }
}
