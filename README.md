# 🛡️ AbessVPN Cyber - Commercial Edition v2.5

Une solution VPN professionnelle, commerciale et ultra-sécurisée complète comprenant :
1. **L'Application Mobile Flutter Cyber Xray/VLESS** (`abess_vpn`) avec support multi-protocoles, gestion par Token, Kill Switch, Speed Test intégré, et injection SNI Host.
2. **Le Serveur Maître & Panel Commercial** (`AbessVpn Server Panel`) gérant l'authentification VLESS/WebSocket, l'attribution des tokens, la télémesure en temps réel, le système de revendeurs avec crédits Go, et le contrôle anti-fraude d'appareils.

---

## 🚀 Architecture Globale

```
+--------------------------------------------------------+
|             Application Mobile Flutter                 |
|  - Moteur V2Ray/Xray (VLESS, VMess, Trojan, SS)        |
|  - Speed Test Réel (Ping, Download, Upload)            |
|  - Protection par Token & Lien Crypté (abess://)       |
+---------------------------+----------------------------+
                            | (HTTP REST API / WebSocket)
                            v
+--------------------------------------------------------+
|           AbessVPN Server Panel & Core API             |
|  - Port: 3000 (Express + TypeScript + WS /@abess237)   |
|  - Super Admin: rigomanga4@gmail.com                   |
|  - Gestion des Revendeurs & Crédits Go                 |
|  - Anti-Fraude Appareil (Essai 1 Go / 24h)            |
+--------------------------------------------------------+
```

---

## 📱 Application Mobile Flutter (`abess_vpn`)

### Fonctionnalités
- **Moteur VPN Xray/VLESS** : Support natif VLESS + WebSocket + TLS 1.3 avec injection SNI Host (zero-rating).
- **Mode Multi-Protocoles Autonome** : Mode de secours "Zero-Token" permettant de configurer manuellement n'importe quel serveur (VLESS, VMess, Trojan, Shadowsocks) avec transports (WS, gRPC, xHTTP, TCP).
- **Speed Test Cyber Intégré** : Mesure en temps réel de la latence Ping, du débit montant (Upload) et descendant (Download).
- **Gestion des Quotas & Licences** : Affichage dynamique de la consommation en Go et de la durée restante avant expiration.
- **Sécurité & Stabilité** : Kill Switch anti-fuite de données, Multiplexage TCP (Mux) et Reconnexion Automatique.
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
- **Super Admin Email** : `rigomanga4@gmail.com`
- **Mot de passe par défaut** : `abess237`

### Modèle Commercial & Revendeurs
- **Super Administrateur** : Contrôle total du serveur, gestion des revendeurs, recharge de leurs crédits en Gigas (Go), visualisation de la consommation globale du réseau.
- **Revendeurs** : Peuvent créer et vendre des tokens clients. Chaque création de token déduit automatiquement le quota équivalent de leur solde de crédits Go. Les revendeurs ne voient **jamais** l'adresse IP ni l'infrastructure maîtresse du serveur.
- **Tokens Clients** : Définissent la limite de données (ex: 10 Go, 50 Go, 100 Go), la durée de validité (ex: 30 jours) et le nombre maximum d'appareils autorisés simultanément.
- **Essai Gratuit Anti-Fraude** : Distribution automatique d'un pass découverte de 1 Go / 24h verrouillé par l'empreinte matérielle de l'appareil (`deviceId`).

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
