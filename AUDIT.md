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
