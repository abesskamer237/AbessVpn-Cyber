# Taille des APK Android

L’APK ARM64 2.5.1 mesuré faisait 55 768 409 octets (55,77 Mo). Ses bibliothèques natives `libgojni.so`, `libflutter.so` et `libapp.so` représentaient à elles seules environ 48 Mo, stockés sans compression. Les bases GeoIP/GeoSite ajoutaient environ 5 Mo compressés et étaient copiées sur le téléphone alors que les profils de l’application ne les utilisent pas.

Depuis 2.5.2 :

- `useLegacyPackaging = true` compresse les bibliothèques natives dans le téléchargement. Android les extrait lors de l’installation ; les binaires du moteur VPN sont conservés.
- `geoip.dat` et `geosite.dat` sont exclus des assets. Les configurations VLESS/SSH sont générées sans règles GeoIP/GeoSite. Le plugin copie ces fichiers optionnels seulement lorsqu’ils sont présents.
- La réduction des polices Material est activée. Les dépendances inutilisées Google Fonts et Cupertino Icons sont retirées. La réduction R8 des classes et ressources était déjà activée par Flutter et reste active.
- Les APK ARM32 et ARM64 restent distincts. Le repli de mise à jour GitHub sélectionne l’architecture annoncée par Android ; un appareil inconnu reçoit la variante universelle plutôt qu’un APK arbitraire incompatible.

Les workflows vérifient la présence des moteurs natifs, la compression des `.so`, l’absence des bases géographiques et les budgets de téléchargement : ARM64 25 Mo, ARM32 23 Mo, x86_64 30 Mo, universel 75 Mo. Un dépassement empêche la publication. Les tailles réellement obtenues sont publiées dans `APK-SIZES.md` et `APK-SIZES.json` avec chaque release ; les nombres ne sont pas des promesses avant compilation.

La variante universelle regroupe plusieurs architectures et est plus volumineuse. Pour réduire le téléchargement, choisir ARM64 pour `arm64-v8a` et ARM32 pour `armeabi-v7a`. La taille installée baisse moins que celle du fichier APK, car Android doit extraire les moteurs natifs. Les caches et profils de l’application prennent également de la place.

Les bases géographiques ne doivent pas être réintroduites dans la configuration sans réviser leur exclusion : le contrôle de publication signale les références `geoip:` et `geosite:` dans le code. Les tests de connexion SSH/TLS/Xray et Flutter restent obligatoires avant les builds. Une recette sur téléphone reste nécessaire pour vérifier l’installation, le chargement des bibliothèques et le VPN sur Android réel.

La version 2.5.3 supprime également, au démarrage, les copies GeoIP/GeoSite laissées par les anciennes versions dans les répertoires d’assets propres à l’application. Aucun profil, identifiant ni autre fichier utilisateur n’est supprimé.
