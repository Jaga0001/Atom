import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class CsvLoaderResult {
  final List<String> headers;
  final List<Map<String, String>> rows;
  CsvLoaderResult({required this.headers, required this.rows});
}

class CsvLoader {
  /// Loads metrics_2.csv from assets. Ensure pubspec lists assets/metrics_2.csv.
  static Future<CsvLoaderResult> loadFromAssets({
    String assetPath = 'assets/metrics_2.csv',
  }) async {
    final csvString = await rootBundle.loadString(assetPath);
    return parseCsv(csvString);
  }

  /// Parse CSV content into headers and row maps (string values).
  static CsvLoaderResult parseCsv(String csvString) {
    final lines = const LineSplitter()
        .convert(csvString)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return CsvLoaderResult(headers: const [], rows: const []);
    }

    List<String> splitCsvLine(String line) {
      // Basic CSV split handling quoted fields and commas.
      final result = <String>[];
      final buffer = StringBuffer();
      bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        final char = line[i];
        if (char == '"') {
          // Toggle quotes or escape double quotes inside quoted string
          if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
            buffer.write('"');
            i++; // skip escaped quote
          } else {
            inQuotes = !inQuotes;
          }
        } else if (char == ',' && !inQuotes) {
          result.add(buffer.toString());
          buffer.clear();
        } else {
          buffer.write(char);
        }
      }
      result.add(buffer.toString());
      return result.map((s) => s.trim()).toList();
    }

    final headers = splitCsvLine(lines.first);
    final rows = <Map<String, String>>[];
    for (int i = 1; i < lines.length; i++) {
      final cols = splitCsvLine(lines[i]);
      final map = <String, String>{};
      for (int j = 0; j < headers.length; j++) {
        final key = headers[j];
        final val = j < cols.length ? cols[j] : '';
        map[key] = val;
      }
      rows.add(map);
    }

    return CsvLoaderResult(headers: headers, rows: rows);
  }
}
