/// Name: Shock corpus check
/// Parent: Parity shock planner
/// Description: Audits evasion feasibility on locally available chart streams.
library;

import 'dart:convert';
import 'dart:io';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_shocks.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local shock charts', () {
    final methods = <String, int>{};
    var charts = 0, total = 0, blocked = 0;
    final problems = <String>[];
    for (final f in Directory('assets/steps').listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final data = jsonDecode(f.readAsStringSync());
      for (final m in ['sp', 'dp']) {
        for (final e in (data['charts'][m] as Map).entries) {
          final notes = ChartSteps.fromJson(e.value).notes;
          final groups = <int, Set<int>>{};
          for (final n in notes.where((n) => n.type == StepType.mine)) {
            (groups[(n.second * 1000).round()] ??= {}).add(n.col);
          }
          if (!groups.values.any((g) => g.length >= 3)) continue;
          final mode = m == 'sp' ? Modes.singles : Modes.doubles;
          final result = analyseParity(notes, mode);
          final plans = planShockEvasions(notes, result.stances, mode);
          charts++;
          total += plans.length;
          for (final p in plans) {
            methods.update(p.method.name, (v) => v + 1, ifAbsent: () => 1);
            if (!p.feasible) {
              blocked++;
              if (problems.length < 15) {
                problems.add('${data['name']} $m ${e.key} ${p.second}');
              }
              continue;
            }
            expect(p.amount(p.second), 1);
            for (final n in notes.where(
                (n) => n.type != StepType.mine && p.columns.contains(n.col))) {
              expect(p.amount(n.second), 0,
                  reason:
                      '${data['name']} $m ${e.key} note ${n.second} shock ${p.second}');
            }
          }
        }
      }
    }
    // ignore: avoid_print
    print(jsonEncode({
      'charts': charts,
      'shocks': total,
      'methods': methods,
      'infeasible': blocked,
      'examples': problems
    }));
  });
}
