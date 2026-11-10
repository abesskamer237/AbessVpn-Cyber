/**
 * RETIRED LEGACY SERVER
 *
 * Production control plane: https://github.com/abesskamer237/AbessVpn-Server-Panel
 *
 * This repository is the Android client. The previous server implementation
 * contained demo credentials and obsolete public endpoints. It is intentionally
 * disabled so that npm start, Docker and old systemd units fail closed.
 */
console.error(
  '[ABESS VPN] This legacy server is retired. Deploy the control plane from ' +
  'https://github.com/abesskamer237/AbessVpn-Server-Panel instead.'
);
throw new Error('ABESS VPN legacy server retired. Use AbessVpn-Server-Panel.');

export {};
