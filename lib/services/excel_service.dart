import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ExcelService {
  /// Get the workspace data directory (stores files in project/data folder)
  static Future<String> getDocumentsDirectory() async {
    // Try to get the current working directory (workspace)
    try {
      final currentDir = Directory.current.path;
      final dataDir = path.join(currentDir, 'data');
      final dir = Directory(dataDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dataDir;
    } catch (e) {
      // Fallback to app documents directory if workspace not available
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    }
  }

  static Future<String> getExcelFilePath(String fileName) async {
    final dir = await getDocumentsDirectory();
    return path.join(dir, fileName);
  }

  static Future<Excel> loadExcelFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      return Excel.decodeBytes(bytes);
    } else {
      // Create new Excel file (Sheet1 is created by default)
      return Excel.createExcel();
    }
  }

  static Future<void> saveExcelFile(Excel excel, String filePath) async {
    final file = File(filePath);
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
  }

  static Excel createExcelWithHeaders(List<String> headers, String sheetName) {
    final excel = Excel.createExcel();
    // Use the default Sheet1 or the provided sheet name
    final actualSheetName = sheetName == 'Sheet1' ? 'Sheet1' : sheetName;
    if (actualSheetName != 'Sheet1') {
      excel.delete('Sheet1');
    }
    
    final sheet = excel[actualSheetName];
    
    // Add headers
    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    
    return excel;
  }

  static List<Map<String, dynamic>> excelToMapList(Excel excel, String sheetName) {
    final sheet = excel[sheetName];
    if (sheet == null) return [];

    final List<Map<String, dynamic>> data = [];
    
    if (sheet.maxRows == 0) return data;

    // Get headers from first row
    final headers = <String>[];
    // Iterate through columns until we find an empty one
    int col = 0;
    while (true) {
      try {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        if (cell.value != null && cell.value.toString().trim().isNotEmpty) {
          headers.add(cell.value.toString());
          col++;
        } else {
          break; // Stop at first empty column
        }
      } catch (e) {
        break; // Stop if we go out of bounds
      }
    }

    // Read data rows
    for (int row = 1; row < sheet.maxRows; row++) {
      final rowData = <String, dynamic>{};
      bool hasData = false;
      
      for (int col = 0; col < headers.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        final value = cell.value;
        if (value != null) {
          rowData[headers[col]] = value.toString();
          hasData = true;
        } else {
          rowData[headers[col]] = '';
        }
      }
      
      if (hasData) {
        data.add(rowData);
      }
    }

    return data;
  }

  static void mapListToExcel(Excel excel, String sheetName, List<Map<String, dynamic>> data, List<String> headers) {
    final sheet = excel[sheetName];
    
    // Ensure headers are written
    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    
    // Clear existing data rows (keep headers)
    if (sheet.maxRows > 1) {
      for (int row = 1; row < sheet.maxRows; row++) {
        for (int col = 0; col < headers.length; col++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value = null;
        }
      }
    }

    // Write data
    for (int row = 0; row < data.length; row++) {
      final rowData = data[row];
      for (int col = 0; col < headers.length; col++) {
        final header = headers[col];
        final value = rowData[header]?.toString() ?? '';
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1))
            .value = TextCellValue(value);
      }
    }
  }
}

