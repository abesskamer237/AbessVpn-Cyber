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
