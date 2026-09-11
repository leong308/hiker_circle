import 'package:flutter/material.dart';
import '../../core/widgets/loading_toast.dart';
import '../Model/trail_precautions.dart';
import '../Model/precaution_check_service.dart';
import '../Model/trail_models.dart';

Future<bool> confirmHikePrecautions(BuildContext context, Trail trail) async {
  final check = PrecautionCheckService.check(trail);
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => FutureBuilder<List<TrailPrecaution>>(
          future: check,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Dialog(
                child: HikerCircleLoadingToast(
                  message: 'Checking hike precautions…',
                ),
              );
            }
            final cautions = snapshot.data!;
            return AlertDialog(
              title: const Text('Before you set off'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cautions.isEmpty)
                      const Text(
                        'No specific advisories identified from the available forecast. Conditions can change.',
                      ),
                    for (final caution in cautions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text('${caution.title}\n${caution.message}'),
                      ),
                    const Text(
                      'Forecast guidance is not a safety clearance. Check official warnings and trail closures.',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Go back'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('I have reviewed these'),
                ),
              ],
            );
          },
        ),
      ) ??
      false;
}
