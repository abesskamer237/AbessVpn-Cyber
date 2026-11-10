# Audit du 10 novembre 2026

## Corrections

- Les deux workflows Android utilisent désormais Flutter **3.41.0** au lieu de 3.22.3, incompatible avec le `pubspec.lock` existant (Dart >=3.11, Flutter >=3.41).
- Suppression du domaine API implicite dans le client et des replis vers un domaine fixe dans les builds. `VPN_DOMAIN` doit être configuré dans les variables GitHub avant de compiler un APK officiel.
- Validation de l'URL du client : HTTPS, hôte présent, sans identifiants, chemin, paramètres de requête ni fragment. Sans configuration valide, aucune URL serveur n'est sélectionnée.
- Correction des accès Kotlin `flutter.versionCode` et `flutter.versionName` : ce sont des propriétés dans Flutter 3.41.0, et non des fonctions. Vérification auprès du code officiel Flutter et de son modèle Gradle.
- Permission Android INTERNET déclarée explicitement et trafic HTTP en clair désactivé. La sauvegarde Android était déjà désactivée.

## Vérifications

- `npm ci` : installation verrouillée réussie.
- Vérification TypeScript du fichier serveur historique avec les options du workflow : réussie. Ce serveur est volontairement désactivé et ne doit pas être redémarré.
- `npm audit` : aucune vulnérabilité connue dans les dépendances Node installées.
- YAML des workflows et `git diff --check` : valides.
- Examen du stockage sécurisé des profils, des imports et de la configuration Android.

## Non vérifié et prérequis

Flutter n'est pas installé et le téléchargement officiel du SDK est refusé par le proxy sur `storage.googleapis.com` (HTTP 403). Les changements Dart/Android n'ont donc pas été compilés ni validés par `flutter analyze`, `flutter test` ou un APK. La compatibilité effective des plugins avec le SDK fixé doit être confirmée par ces commandes après rétablissement de l'accès :

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug --dart-define=ABESS_API_BASE_URL=https://VOTRE_DOMAINE
```

La construction Android exige aussi le SDK Android et Java 17. Les releases exigent les secrets de signature persistants déjà prévus par les workflows. Les tests VPN sur appareil réel, de changement d'IP et d'application du quota restent nécessaires. Aucun APK ni aucune release n'a été publié.

## Refonte visuelle

- Identité cohérente avec le panneau : surfaces bleu nuit, émeraude, thème clair et typographie système lisible. L'affichage initial ne dépend plus d'un téléchargement de polices Google.
- Nouvelle carte d'accueil présentant l'état réel du moteur VPN, le serveur sélectionné et l'accès à sa sélection. Elle ne simule pas une connexion active.
- Navigation Material 3, retour haptique sur changement d'onglet et transitions de glissement/fondu.
- Animations désactivées selon le réglage système de réduction des mouvements ; contrôle principal utilisable au clavier et annoncé aux lecteurs d'écran.
- Tests de widget ajoutés pour l'état déconnecté, le changement d'état, l'action de sélection et les petits écrans avec texte agrandi.

Un parseur Dart indépendant a vérifié la syntaxe des fichiers modifiés sans erreur. Cela ne remplace pas `flutter analyze`, `flutter test` et une compilation Android : ces vérifications restent bloquées localement par l'accès au SDK mentionné ci-dessus. Les workflows GitHub exécutent les tests Flutter avant la construction de l'APK.

## Version 2.4.0 — fiabilité et confidentialité

- Sources de mise à jour limitées à l’origine HTTPS du control plane et aux releases officielles GitHub du projet. Le serveur d’un profil VPN importé ne peut plus annoncer une mise à jour.
- Expurgation centralisée des journaux et partage explicite d’un rapport de support. Tokens, URI de configuration, UUID, IPv4 et champs de secrets sont masqués.
- Requêtes de consommation sérialisées, protection contre la réponse d’une ancienne licence après changement de profil et déconnexion après deux minutes sans vérification serveur d’une licence gérée.
- Vérification de disponibilité du nœud affecté par une route POST, sans token dans l’URL.
- Refus de VLESS sans TLS dans l’application ; guide VPN permanent/blocage système, ouverture des paramètres Android par canal natif et documentation de recette sur appareil.
- Version 2.4.0, versionCode 2004000 partagé par les workflows, vérification des signatures APK, manifeste SHA256 et attestation de provenance pour la release. Actions épinglées à leurs commits et Dependabot configuré.

La syntaxe des sources Dart modifiées et des nouveaux tests est validée par un parseur indépendant. Le code TypeScript historique et l’audit npm passent. **Les tests Flutter, la compilation APK, l’installation Android et les tests de fuite/reconnexion ne sont pas exécutés dans ce cloud** : le SDK est toujours bloqué au téléchargement. Les workflows GitHub doivent être suivis après le push ; aucun APK publié n’est annoncé comme validé localement.

### Consigne finale : règlement manuel uniquement

La page Outils affiche les numéros MTN MoMo 681328753 (manga Ghislain) et Orange Money 695140419 (mengue belinga), avec copie explicite et contact du support. Aucun SDK, lien de prélèvement ou paiement automatique n’est intégré. Le test de widget correspondant est ajouté ; il reste à exécuter avec Flutter lorsque le SDK sera accessible.

## SSH ABESS — application 2.5.0

Client DartSSH2 indépendant, import du JSON du panel, SSH TCP et WebSocket/TLS, vérification de la clé SHA-256 et du certificat TLS, profils conservés dans le stockage sécurisé. Proxy SOCKS local authentifié vers le moteur Xray Android ; DNS UDP converti en TCP dans SSH, autre UDP bloqué et aucune sortie directe. Les sockets de l’application sont exclus du VPN pour éviter une boucle.

Preuves locales : client Dart compilé et exécuté contre un pair SSH2 réel en TCP et WSS ; refus de certificat non approuvé et d’empreinte erronée ; trafic HTTP réel ; Xray officiel 26.7.28 relié au proxy Dart, HTTP traversant la chaîne complète et DNS UDP converti en TCP via SSH. Analyse Dart des sources modifiées : aucune erreur. Ces contrôles sont intégrés aux workflows avant construction/publication. La recette Android sur téléphone reste à faire ; aucune validation d’autonomie ou de changement de réseau n’est prétendue exécutée.
