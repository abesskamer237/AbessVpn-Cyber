# 🛡️ AbessVPN Cyber - Commercial Edition v2.5

Une solution VPN comprenant :
1. **L'application Android Flutter/Xray** (`abess_vpn`) : gestion par token, import de profils VLESS/VMess/Trojan/Shadowsocks, Kill Switch, test de débit et reconnexion.
2. **Le dépôt serveur dédié** (`AbessVpn-Server-Panel`) : API de licences, panneau d'administration, statistiques Xray, gestion des quotas et déploiement Docker/Caddy.

---

## 🚀 Architecture Globale

```
+--------------------------------------------------------+
|             Application Mobile Flutter                 |
|  - VLESS, VMess, Trojan, Shadowsocks                    |
|  - WS, gRPC, HTTPUpgrade, XHTTP, RAW/TCP, mKCP/UDP    |
|  - Licence par token et lien chiffré abess://           |
+---------------------------+----------------------------+
                            | HTTPS / API REST
                            v
+--------------------------------------------------------+
|           Dépôt AbessVpn-Server-Panel                   |
|  - API + React Admin + stockage persistant Docker      |
|  - Xray-core + Caddy + Docker Compose                  |
|  - Expiration, quota, appareils et compteurs réels     |
+--------------------------------------------------------+
```

---

## 📱 Application Mobile Flutter (`abess_vpn`)

### Fonctionnalités
- **Protocoles d'accès** : VLESS, VMess, Trojan et Shadowsocks (AEAD).
- **Transports TLS/TCP** : WebSocket, gRPC, HTTPUpgrade et XHTTP sur le port HTTPS du serveur.
- **TCP et UDP natifs supplémentaires** : VMess RAW/TCP sur le port 10060 et VMess mKCP/UDP sur le port 10061 ; Shadowsocks natif TCP + UDP sur le port 10050. Ouvre ces ports dans le pare-feu du VPS si ces modes sont activés.
- **Import de profils** : liens `vless://`, `vmess://`, `trojan://` et `ss://`. Les profils Reality et les liens Shadowsocks qui requièrent un plugin externe ne sont pas convertis automatiquement.
- **Multiplexage** : MUX/XUDP disponible selon le transport ; désactivé pour gRPC et mKCP.
- **Speed Test Cyber Intégré** : Mesure en temps réel de la latence Ping, du débit montant (Upload) et descendant (Download).
- **Gestion des quotas & licences** : Affichage de la consommation comptabilisée par Xray et de l'expiration de la licence.
- **Sécurité & stabilité** : Kill Switch, MUX lorsque compatible et reconnexion automatique.
- **Limite de compatibilité** : Hysteria, WireGuard et TUN ne sont pas présentés comme options actives dans cette version : ils nécessitent une configuration/gestion de clés et une intégration client dédiées.
- **Support Client WhatsApp Direct** : Boutons d'assistance directe vers WhatsApp (+237 695 14 04 19) et lien vers la communauté officielle.

### Compilation et Build Flutter

#### Prérequis
- Flutter SDK >= 3.10.0
- Android SDK (Android 5.0+, API 21+)

#### Commandes de build
```bash
# Vérifier et analyser le code Dart
flutter analyze

# Lancer les tests unitaires
flutter test

# Générer l'APK Android Debug
flutter build apk --debug

# Générer l'APK Android Release optimisé
flutter build apk --release
```

---

## 🖥️ Serveur Maître & Panel Commercial (`server.ts`)

### Identifiants Administrateur

N'utilise pas de compte ou mot de passe d'exemple en production. Pour le déploiement du dépôt serveur dédié, renseigne `ADMIN_EMAIL` et `ADMIN_INITIAL_PASSWORD` dans les secrets GitHub Actions ; le mot de passe initial doit comporter au moins 16 caractères. Le secret `MASTER_SECRET` doit rester stable après la création des liens chiffrés `abess://`. Ne place aucun mot de passe dans ce README, dans le code ou dans un commit.

### Modèle Commercial & Revendeurs
- **Super Administrateur** : Contrôle total du serveur, gestion des revendeurs, recharge de leurs crédits en Gigas (Go), visualisation de la consommation globale du réseau.
- **Revendeurs** : Peuvent créer et vendre des tokens clients. Chaque création de token déduit automatiquement le quota équivalent de leur solde de crédits Go. Les revendeurs ne voient **jamais** l'adresse IP ni l'infrastructure maîtresse du serveur.
- **Tokens Clients** : Définissent la limite de données (ex: 10 Go, 50 Go, 100 Go), la durée de validité (ex: 30 jours) et le nombre maximum d'appareils autorisés simultanément.
- **Essai gratuit** : la route de test gratuit du dépôt serveur dédié reste désactivée tant que le contrôle anti-fraude n'est pas complètement activé ; l'application ne doit pas afficher un essai fonctionnel lorsqu'il ne l'est pas.

---

## 🛠️ Installation du Serveur sur un VPS Linux

### Option 1 : Installation Automatique 1-Click (Recommandée)
Sur votre serveur VPS (Ubuntu 20.04/22.04/24.04 ou Debian 11/12) :

```bash
git clone https://github.com/abesskamer237/AbessVpn-Cyber.git
cd AbessVpn-Cyber
chmod +x install.sh
sudo ./install.sh
```

Le script installe automatiquement Node.js 22 LTS, NGINX, Certbot SSL, configure le service Systemd `abessvpn.service` et démarre le serveur.

---

### Option 2 : Déploiement avec Docker & Docker Compose

```bash
# Lancer en arrière-plan
docker-compose up -d --build

# Vérifier les logs du serveur
docker-compose logs -f
```

---

### Option 3 : Installation Manuelle (Systemd)

```bash
# 1. Installer Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# 2. Installer les dépendances
npm install

# 3. Démarrer en développement / test
npm start

# 4. Activer le service Systemd
cp abessvpn.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable abessvpn
systemctl start abessvpn
```

---

## 🔒 Configuration Reverse Proxy NGINX & SSL/TLS

Le fichier `nginx.conf` fourni gère la terminaison SSL/TLS Let's Encrypt et le proxying WebSocket sur `/@abess237` :

```nginx
# Copier la configuration vers NGINX
cp nginx.conf /etc/nginx/sites-available/abessvpn
ln -s /etc/nginx/sites-available/abessvpn /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# Obtenir un certificat SSL gratuit avec Certbot
certbot --nginx -d vpn.votre-domaine.com
```

---

## 📡 Spécification des Endpoints API REST

| Méthode | Endpoint | Description |
|---|---|---|
| `GET` | `/api/v1/ping` | Vérification de la disponibilité et latence du serveur |
| `GET` | `/api/v1/speedtest/download` | Test de débit descendant (Download) |
| `POST` | `/api/v1/speedtest/upload` | Test de débit montant (Upload) |
| `POST` | `/api/v1/auth/login` | Connexion Administrateur / Revendeur |
| `POST` | `/api/v1/auth/token` | Validation de licence client mobile |
| `POST` | `/api/v1/client/telemetry` | Synchronisation consommations & quotas |
| `POST` | `/api/v1/client/claim-free-trial` | Activation du pass 1 Go / 24h anti-fraude |
| `POST` | `/api/v1/client/create-token` | Génération de token client avec quota/durée |
| `GET` | `/api/v1/admin/resellers` | Liste des revendeurs (Super Admin) |
| `POST` | `/api/v1/admin/resellers` | Création d'un revendeur |
| `PUT` | `/api/v1/admin/resellers/:id/credit` | Recharge du solde de crédits en Go |
| `GET` | `/api/v1/admin/tokens` | Consultation des tokens attribués |
| `GET` | `/api/v1/admin/stats` | Métriques et données réseau globales |

---

## 📞 Support & Assistance Technique

- **WhatsApp Support** : [+237 695 14 04 19](https://wa.me/237695140419)
- **Communauté Officielle** : [Groupe WhatsApp AbessVPN](https://chat.whatsapp.com/IR0pjvSbTvL0Wp4YlbCjhF)

---
© 2026 AbessVPN Cyber - Tous droits réservés.
