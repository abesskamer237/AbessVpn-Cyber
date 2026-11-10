import 'package:flutter/material.dart';
class SafetyCenter extends StatelessWidget {
  const SafetyCenter({super.key,required this.onOpenSettings,required this.onShareDiagnostics});
  final VoidCallback onOpenSettings;
  final VoidCallback onShareDiagnostics;
  @override
  Widget build(BuildContext context) {
    final theme=Theme.of(context);
    return Container(
      padding:const EdgeInsets.all(20),
      decoration:BoxDecoration(color:theme.colorScheme.surfaceContainer,borderRadius:BorderRadius.circular(20),border:Border.all(color:theme.colorScheme.outlineVariant)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Icon(Icons.verified_user_outlined,color:theme.colorScheme.primary),const SizedBox(width:10),Expanded(child:Text('Protection et confidentialité',style:theme.textTheme.titleMedium))]),
        const SizedBox(height:12),
        const Text('1. Importez votre accès depuis votre revendeur.\n2. Connectez le VPN et vérifiez votre navigation.\n3. Pour bloquer le trafic lors d’une coupure, activez le VPN permanent et « Bloquer les connexions sans VPN » dans Android.'),
        const SizedBox(height:12),
        const Text('Le statut connecté ne constitue pas un test de fuite DNS ou IPv6. Une vérification sur appareil reste nécessaire.',style:TextStyle(fontSize:11)),
        const SizedBox(height:16),
        Wrap(spacing:10,runSpacing:10,children:[
          OutlinedButton.icon(onPressed:onOpenSettings,icon:const Icon(Icons.settings_outlined),label:const Text('Paramètres VPN Android')),
          OutlinedButton.icon(onPressed:onShareDiagnostics,icon:const Icon(Icons.support_agent_outlined),label:const Text('Partager un diagnostic expurgé')),
        ]),
      ]),
    );
  }
}
