import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ManualPaymentContact {
  const ManualPaymentContact(this.label, this.number, this.holder);
  final String label;
  final String number;
  final String holder;
}

/// Instructions only: no payment SDK, USSD execution or automatic validation.
class ManualPaymentInfo extends StatelessWidget {
  const ManualPaymentInfo({super.key, required this.onContactSupport});
  final VoidCallback onContactSupport;
  static const contacts = [
    ManualPaymentContact('MTN MoMo', '681328753', 'manga Ghislain'),
    ManualPaymentContact('Orange Money', '695140419', 'mengue belinga'),
  ];
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Paiement manuel', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        const Text('Demandez le montant à votre revendeur. Effectuez le transfert vous-même, puis transmettez sa référence pour vérification. Votre licence sera fournie ou renouvelée après confirmation manuelle.'),
        const SizedBox(height: 12),
        for (final contact in contacts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${contact.label} · ${contact.number}'),
            subtitle: Text('Bénéficiaire : ${contact.holder}'),
            trailing: IconButton(
              tooltip: 'Copier le numéro ${contact.label}',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: contact.number));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro copié. Vérifiez le bénéficiaire avant tout transfert.')));
              },
            ),
          ),
        const SizedBox(height: 8),
        const Text('Aucun paiement ni débit automatique dans l’application. Vérifiez le numéro et le nom du bénéficiaire avant confirmation.', style: TextStyle(fontSize: 11)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: onContactSupport, icon: const Icon(Icons.support_agent_outlined), label: const Text('Contacter le support')),
      ]),
    );
  }
}
