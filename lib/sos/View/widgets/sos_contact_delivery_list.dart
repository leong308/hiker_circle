import 'package:flutter/material.dart';

import '../../Model/sos_models.dart';

/// Identifies the exact saved contact and separates unknown outcomes from retryable failures.
class SosContactDeliveryList extends StatelessWidget {
  /// Shows the original contact index alongside the current provider confirmation.
  const SosContactDeliveryList({super.key, required this.dispatches});

  final List<SosContactDispatch> dispatches;

  /// Builds a compact, accessible result list for the SOS event details.
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < dispatches.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            child: Text(
              '${dispatches[i].contactIndex > 0 ? dispatches[i].contactIndex : i + 1}',
            ),
          ),
          title: Text(dispatches[i].contactName),
          subtitle: Text(
            '${dispatches[i].phoneNumber}\n${dispatches[i].confirmationLabel}'
            '${dispatches[i].errorMessage?.isNotEmpty == true && !dispatches[i].wasSent ? '\n${dispatches[i].errorMessage}' : ''}',
          ),
          trailing: Icon(
            dispatches[i].wasSent
                ? Icons.check_circle_rounded
                : dispatches[i].isUnconfirmed || dispatches[i].isConfirming
                ? Icons.hourglass_top_rounded
                : Icons.error_outline_rounded,
            color: dispatches[i].wasSent ? Colors.green : Colors.orange,
          ),
        ),
    ],
  );
}
