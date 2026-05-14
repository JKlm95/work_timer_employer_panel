import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/work_email_validation.dart';
import 'package:work_timer_employer_panel/models/employee_work_email_index.dart';

void main() {
  group('isPlausibleWorkEmail', () {
    test('accepts normal address', () {
      expect(isPlausibleWorkEmail('kuba@firma.pl'), true);
    });
    test('rejects missing domain dot', () {
      expect(isPlausibleWorkEmail('kuba@firma'), false);
    });
    test('rejects empty', () {
      expect(isPlausibleWorkEmail(''), false);
    });
  });

  group('normalizeWorkEmailLower', () {
    test('trims and lowercases', () {
      expect(normalizeWorkEmailLower('  Kuba@Firma.PL '), 'kuba@firma.pl');
    });
  });

  group('EmployeeWorkEmailIndex.fromDoc', () {
    test('parses workspaceIds and dedupes empty strings', () {
      final idx = EmployeeWorkEmailIndex.fromDoc('kuba@firma.pl', {
        'uid': 'u1',
        'workEmailLower': 'kuba@firma.pl',
        'domain': 'firma.pl',
        'workspaceIds': ['w1', '', 'w1', 'w2'],
      });
      expect(idx.uid, 'u1');
      expect(idx.workEmailLower, 'kuba@firma.pl');
      expect(idx.domain, 'firma.pl');
      expect(idx.workspaceIds, ['w1', 'w2']);
    });
  });
}
