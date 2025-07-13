import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'scan_model.dart';

class ScanHistoryService {
  static const String _historyKey = 'scan_history';

  // Save a scan entry to history
  Future<void> addScan(String value, [String formatName = "Unknown"]) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    
    // Create new entry
    final entry = ScanEntry(
      value: value,
      timestamp: DateTime.now(),
      formatName: formatName,
    );
    
    // Add to list
    history.add(entry);
    
    // Save updated list
    List<String> jsonList = history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_historyKey, jsonList);
  }

  // Get all scan history
  Future<List<ScanEntry>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_historyKey) ?? [];
    
    // Convert from JSON to objects
    return jsonList
        .map((jsonString) => ScanEntry.fromJson(jsonDecode(jsonString)))
        .toList();
  }

  // Clear history
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
} 