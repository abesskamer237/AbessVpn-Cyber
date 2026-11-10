import 'package:flutter/material.dart';

/// Presentation only: the VPN engine remains the source of connection state.
class ConnectionOverview extends StatelessWidget {
  const ConnectionOverview({
    super.key,
    required this.connected,
    required this.connecting,
    required this.onChooseServer,
    this.serverName,
  });

  final bool connected;
  final bool connecting;
  final String? serverName;
  final VoidCallback onChooseServer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final accent = connecting
        ? const Color(0xFFD97706)
        : connected
            ? const Color(0xFF10B981)
            : theme.colorScheme.primary;
    final status = connecting ? 'Connexion en cours' : connected ? 'VPN connecté' : 'Déconnecté';
    return AnimatedContainer(
      duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF102D30), const Color(0xFF0C1828)]
              : [const Color(0xFFE4F8EF), const Color(0xFFF5FAFF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text('VOTRE ESPACE VPN',
                  style: TextStyle(fontSize: 10, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: accent)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Votre connexion,\nen toute simplicité.',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.8, height: 1.2)),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 240),
            child: Align(
              key: ValueKey(status),
              alignment: Alignment.centerLeft,
              child: Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    Container(width: 7, height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: connected || connecting ? accent : theme.colorScheme.outline)),
                    const SizedBox(width: 7),
                    Text(status, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.dns_outlined, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SERVEUR SÉLECTIONNÉ', style: theme.textTheme.labelSmall?.copyWith(fontSize: 8, letterSpacing: .8, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(serverName ?? 'Ajoutez votre premier accès', maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: serverName == null ? 'Choisir un serveur' : 'Changer de serveur',
                onPressed: onChooseServer,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
