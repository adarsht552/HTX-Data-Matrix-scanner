class ScanEntry {
  final String value;
  final DateTime timestamp;
  final String formatName;

  ScanEntry({
    required this.value, 
    required this.timestamp,
    this.formatName = "Unknown"
  });

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'formatName': formatName,
    };
  }

  // Create from JSON
  factory ScanEntry.fromJson(Map<String, dynamic> json) {
    return ScanEntry(
      value: json['value'],
      timestamp: DateTime.parse(json['timestamp']),
      formatName: json['formatName'] ?? 'Unknown',
    );
  }
} 