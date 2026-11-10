# Recette Android avant distribution commerciale

Cette recette nécessite un appareil ou émulateur Android, un réseau et un serveur TLS réel. Les tests de syntaxe et de widgets ne la remplacent pas.

| Domaine | Vérifications | Résultat attendu |
| --- | --- | --- |
| Activation | Token valide, inconnu, révoqué, expiré, quota épuisé, appareil supplémentaire | Seul l’accès autorisé est accepté |
| Connexion | WS, gRPC, HTTPUpgrade, XHTTP sur HTTPS | Navigation utilisable, IP de sortie modifiée, certificat correct |
| Quota | Transfert réel puis épuisement côté Xray | Compteurs croissants puis retrait de l’accès |
| Réseau | Wi-Fi/mobile, mode avion, réseau instable | Reconnexion contrôlée sans faux état connecté |
| Vie de l’application | Veille, arrière-plan, économie d’énergie, relance | État cohérent et profils conservés en stockage sécurisé |
| Confidentialité | DNS, IPv4, IPv6 et interruption du serveur | Mesurer les fuites ; ne pas supposer leur absence |
| VPN permanent | VPN permanent et blocage sans VPN activés dans Android | Le système bloque réellement le trafic hors tunnel |
| Mise à jour | APK officiel, autre clé de signature, URL étrangère/HTTP | Origine autorisée ; Android refuse une signature différente |
| Accessibilité | Écran 320 px, texte agrandi, TalkBack, animations réduites | Contrôles lisibles et utilisables |
| Support | Partage explicite du diagnostic | Aucun token, mot de passe, UUID ou IP réutilisable |

Tester Android 6/API 23, une version récente et un appareil physique avec économie d’énergie restrictive, ainsi que les ABI ARM32/ARM64 distribuées.

Après deux minutes sans vérification serveur d’une licence gérée, l’application coupe cette connexion. Seul Android peut imposer le blocage global hors VPN : ce délai applicatif ne remplace pas son verrouillage système.

Après migration d’une ancienne licence VLESS/TCP vers TLS dans le panneau, réimporter la licence. Ne pas distribuer de profil TCP simple comme tunnel chiffré.

## SSH ABESS

- Installer l’APK 2.5.0+, importer les exports TCP et WSS du panel.
- Vérifier sur une autre application le changement d’IP et une navigation HTTPS réelle.
- Confirmer le DNS dans le tunnel, l’absence de sortie UDP directe, IPv4 et IPv6.
- Vérifier le refus d’un certificat TLS invalide ou d’une mauvaise empreinte SSH.
- Suspendre le compte dans le panel et confirmer l’arrêt du VPN. Épuiser le quota, expirer le compte et essayer de reconnecter.
- Vérifier la limite de connexions simultanées avec deux téléphones.
- Tester passage Wi-Fi/mobile, écran éteint, batterie, arrêt/reprise de l’APK et VPN permanent avec blocage sans VPN.
- Confirmer qu’aucun mot de passe, fichier JSON ou URI réutilisable n’apparaît dans les logs/diagnostics.

## SSH-WS HTTP Upgrade brut 2.5.4

- Importer et connecter les modes HTTP 80/85 et TLS brut 443/2084, puis vérifier la navigation depuis une autre application.
- Redémarrer l’APK et vérifier que le mode exact est conservé, sans transformation de HTTP brut en WebSocket encadré.
- Vérifier les anciens exports WSS, le refus de HTTP 200/301/404 au lieu du 101 et les mauvais certificats/empreintes.
- Suspendre le compte, épuiser son quota et vérifier les connexions simultanées sur les différents transports.
