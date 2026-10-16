#!/usr/bin/env bash
# ==============================================================================
# AbessVPN Cyber Server Panel - Script d'Installation Automatique VPS (1-Click)
# Systemes supportés : Ubuntu 20.04/22.04/24.04, Debian 11/12
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}====================================================================${NC}"
echo -e "${GREEN}    INSTALLATION DU SERVEUR MASTER ABESSVPN CYBER COMMERCIAL V2.5   ${NC}"
echo -e "${CYAN}====================================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Erreur : Ce script doit être exécuté en tant que ROOT (sudo ./install.sh)${NC}"
  exit 1
fi

echo -e "${YELLOW}[1/5] Mettre à jour les paquets système...${NC}"
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget git unzip build-essential nginx certbot python3-certbot-nginx

echo -e "${YELLOW}[2/5] Installation de Node.js 22 LTS...${NC}"
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
echo -e "${GREEN}Node.js version : $(node -v)${NC}"

echo -e "${YELLOW}[3/5] Configuration du dossier d'installation /opt/abessvpn-server...${NC}"
INSTALL_DIR="/opt/abessvpn-server"
mkdir -p "$INSTALL_DIR"
cp -r . "$INSTALL_DIR/"
cd "$INSTALL_DIR"

echo -e "${YELLOW}[4/5] Installation des dépendances NPM...${NC}"
npm install --production=false

echo -e "${YELLOW}[5/5] Configuration du service Systemd...${NC}"
cp abessvpn.service /etc/systemd/system/abessvpn.service
systemctl daemon-reload
systemctl enable abessvpn
systemctl restart abessvpn

echo -e "${CYAN}====================================================================${NC}"
echo -e "${GREEN}    INSTALLATION TERMINÉE AVEC SUCCÈS !                            ${NC}"
echo -e "${CYAN}====================================================================${NC}"
echo -e "${YELLOW}Statut du serveur AbessVPN :${NC}"
systemctl status abessvpn --no-pager | head -n 12

echo -e "\n${CYAN}Informations d'accès Administrateur :${NC}"
echo -e "• Port Serveur : 3000"
echo -e "• Super Admin Email : rigomanga4@gmail.com"
echo -e "• Mot de passe par défaut : abess237"
echo -e "• Tester l'API Ping : curl http://localhost:3000/api/v1/ping\n"
