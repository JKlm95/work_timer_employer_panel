import '../core/export/download.dart';
import '../models/work_entry.dart';
import '../models/workspace.dart';
import 'report_calculation_service.dart';

class ExportService {
  void downloadProjectReportCsv({
    required String filename,
    required List<WorkEntry> entries,
    required Map<String, Workspace> workspaceById,
    required bool billableOnly,
  }) {
    final rows = <List<String>>[];
    rows.add([
      'Date',
      'Start',
      'End',
      'Duration (h)',
      'Project',
      'Entry type',
      'Billable',
      'Task',
      'Note',
      'Amount',
      'Currency',
    ]);
    for (final e in entries) {
      final ws = workspaceById[e.workspaceId];
      final hours = e.duration?.inMinutes ?? 0;
      final h = hours / 60.0;
      String amount = '';
      String currency = ws?.currency ?? '';
      if (e.isWorkEntry && e.effectiveBillable) {
        final rate = ws?.hourlyRate;
        if (rate != null && rate > 0) {
          amount = (h * rate).toStringAsFixed(2);
        }
      }
      rows.add([
        _date(e.start),
        _time(e.start),
        e.end != null ? _time(e.end!) : '',
        h.toStringAsFixed(2),
        ws?.name ?? '',
        e.entryType ?? 'work',
        e.effectiveBillable ? 'yes' : 'no',
        e.taskTitle ?? '',
        e.note ?? '',
        amount,
        currency,
      ]);
    }
    downloadTextFile(filename, _toCsv(rows), mimeType: 'text/csv;charset=utf-8');
  }

  void downloadPayrollCsv({
    required String filename,
    required List<PayrollLine> lines,
  }) {
    final rows = <List<String>>[
      [
        'Employee',
        'Company',
        'Groups',
        'Total hours',
        'Billable hours',
        'Non-billable hours',
        'Vacation entries',
        'Sick entries',
        'Amount PLN',
        'Amount EUR',
        'Amount USD',
        'Amount GBP',
      ],
    ];
    for (final line in lines) {
      rows.add([
        line.employeeLabel,
        line.companyName,
        line.groupLabels,
        line.totalHours.toStringAsFixed(2),
        line.billableHours.toStringAsFixed(2),
        line.nonBillableHours.toStringAsFixed(2),
        '${line.vacationCount}',
        '${line.sickCount}',
        _money(line.amountByCurrency['PLN']),
        _money(line.amountByCurrency['EUR']),
        _money(line.amountByCurrency['USD']),
        _money(line.amountByCurrency['GBP']),
      ]);
    }
    downloadTextFile(filename, _toCsv(rows), mimeType: 'text/csv;charset=utf-8');
  }

  static String _money(double? v) {
    if (v == null || v == 0) return '';
    return v.toStringAsFixed(2);
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _toCsv(List<List<String>> rows) {
    return rows.map((row) => row.map(_escapeCell).join(',')).join('\r\n');
  }

  static String _escapeCell(String cell) {
    if (cell.contains(',') || cell.contains('"') || cell.contains('\n') || cell.contains('\r')) {
      return '"${cell.replaceAll('"', '""')}"';
    }
    return cell;
  }
}
