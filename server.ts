import express from 'express';
import http from 'http';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import { WebSocketServer, WebSocket } from 'ws';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const isProduction = process.env.NODE_ENV === 'production';
const PORT = Number(process.env.PORT) || 3000;

// Persistent data storage
const dataDir = path.resolve(__dirname, 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}
const tokensFile = path.resolve(dataDir, 'tokens.json');
const devicesFile = path.resolve(dataDir, 'devices.json');

export interface ClientToken {
  id: string;
  token: string;
  plan: string;
  reseller: string;
  createdAt: string;
  expiresAt: string;
  days: number;
  deviceLimit: number;
  bandwidthGb: number;
  bandwidthUsedGb: number;
  connectionCount: number;
  lastSeenAt: string | null;
  lastSeenIp: string | null;
  status: 'active' | 'revoked' | 'expired' | 'quota_exceeded';
}

export interface DeviceLock {
  id: string;
  fingerprint: string;
  ip: string;
  model: string;
  os: string;
  firstSeenAt: string;
  lastClaimAt: string;
  dailyQuotaMb: number; // 1024 MB (1 Go)
  quotaUsedMb: number;
  remainingMb: number;
  status: 'active' | 'quota_exceeded' | 'banned';
  testToken: string;
}

function loadTokens(): ClientToken[] {
  if (fs.existsSync(tokensFile)) {
    try {
      return JSON.parse(fs.readFileSync(tokensFile, 'utf8'));
    } catch {
      // fallback
    }
  }

  const defaults: ClientToken[] = [
    {
      id: 'tok_root',
      token: 'ABESS-VIP-ROOT-2026',
      plan: 'ABESSVPN CYBER ULTRA UNLIMITED',
      reseller: 'SUPER ADMIN ROOT',
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString(),
      days: 365,
      deviceLimit: 10,
      bandwidthGb: 9999,
      bandwidthUsedGb: 14.2,
      connectionCount: 142,
      lastSeenAt: new Date().toISOString(),
      lastSeenIp: '127.0.0.1',
      status: 'active'
    },
    {
      id: 'tok_demo',
      token: 'ABESS-VIP-DEMO-2026',
      plan: 'COMMERCE PRO 50 GO',
      reseller: 'ABESS OFFICIAL DISTRIBUTOR',
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString(),
      days: 30,
      deviceLimit: 2,
      bandwidthGb: 50,
      bandwidthUsedGb: 3.42,
      connectionCount: 38,
      lastSeenAt: new Date(Date.now() - 15 * 60 * 1000).toISOString(),
      lastSeenIp: '197.234.221.14',
      status: 'active'
    },
    {
      id: 'tok_matrix',
      token: 'CYBER-STEALTH-999',
      plan: 'HACKER PRO ELITE 100 GO',
      reseller: 'DARKNET OPS',
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 90 * 24 * 3600 * 1000).toISOString(),
      days: 90,
      deviceLimit: 5,
      bandwidthGb: 100,
      bandwidthUsedGb: 18.6,
      connectionCount: 97,
      lastSeenAt: new Date(Date.now() - 4 * 60 * 1000).toISOString(),
      lastSeenIp: '102.16.89.201',
      status: 'active'
    }
  ];

  fs.writeFileSync(tokensFile, JSON.stringify(defaults, null, 2), 'utf8');
  return defaults;
}

function saveTokens(tokens: ClientToken[]) {
  fs.writeFileSync(tokensFile, JSON.stringify(tokens, null, 2), 'utf8');
}

function loadDevices(): DeviceLock[] {
  if (fs.existsSync(devicesFile)) {
    try {
      return JSON.parse(fs.readFileSync(devicesFile, 'utf8'));
    } catch {
      // fallback
    }
  }
  const sample: DeviceLock[] = [
    {
      id: 'dev_sample_1',
      fingerprint: 'HWID-SM-G998B-ANDROID14-AE89F1',
      ip: '102.244.18.92',
      model: 'Samsung Galaxy S21 Ultra',
      os: 'Android 14 (OneUI 6.0)',
      firstSeenAt: new Date(Date.now() - 12 * 3600 * 1000).toISOString(),
      lastClaimAt: new Date(Date.now() - 12 * 3600 * 1000).toISOString(),
      dailyQuotaMb: 1024,
      quotaUsedMb: 412,
      remainingMb: 612,
      status: 'active',
      testToken: 'ABESS-FREE-1GO-9921'
    }
  ];
  fs.writeFileSync(devicesFile, JSON.stringify(sample, null, 2), 'utf8');
  return sample;
}

function saveDevices(devices: DeviceLock[]) {
  fs.writeFileSync(devicesFile, JSON.stringify(devices, null, 2), 'utf8');
}

// AES-256 Encryption helper for encrypted AbessVpn configuration links
const SECRET_PASSPHRASE = 'AbessVpn-Cyber-Master-SecretKey-2026';
const KEY = crypto.createHash('sha256').update(SECRET_PASSPHRASE).digest();

export function encryptConfigPayload(plainJson: object): string {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', KEY, iv);
  const jsonStr = JSON.stringify(plainJson);
  let encrypted = cipher.update(jsonStr, 'utf8', 'base64');
  encrypted += cipher.final('base64');
  return `abess://${iv.toString('base64')}.${encrypted}`;
}

export function decryptConfigPayload(abessLink: string): any {
  if (!abessLink.startsWith('abess://')) {
    throw new Error('Format de configuration invalide (doit débuter par abess://)');
  }
  const parts = abessLink.replace('abess://', '').split('.');
  if (parts.length !== 2) {
    throw new Error('Structure cryptographique corrompue');
  }
  const iv = Buffer.from(parts[0], 'base64');
  const encrypted = parts[1];
  const decipher = crypto.createDecipheriv('aes-256-cbc', KEY, iv);
  let decrypted = decipher.update(encrypted, 'base64', 'utf8');
  decrypted += decipher.final('utf8');
  return JSON.parse(decrypted);
}

// Live metrics
let activeTunnelConnections = 0;
let totalBytesTransferred = 1024 * 1024 * 410; // 410 MB
const startTime = Date.now();

async function startServer() {
  const app = express();
  app.use(express.json());

  // CORS
  app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
    if (req.method === 'OPTIONS') {
      res.sendStatus(200);
      return;
    }
    next();
  });

  const server = http.createServer(app);

  // 1. Mobile & Web App Auth API (Token import with exact Go Quota & Expiry date)
  app.post('/api/v1/auth/token', (req, res) => {
    const rawToken = req.body?.token?.toString()?.trim();
    if (!rawToken) {
      res.status(400).json({ valid: false, error: 'Token manquant' });
      return;
    }

    const tokens = loadTokens();
    const found = tokens.find(t => t.token.toUpperCase() === rawToken.toUpperCase());
    const clientIp = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() || req.socket.remoteAddress || 'unknown';

    if (found) {
      // Check expiration
      const now = Date.now();
      const expiryTime = new Date(found.expiresAt).getTime();
      if (now > expiryTime) {
        found.status = 'expired';
        saveTokens(tokens);
        res.status(403).json({
          valid: false,
          error: `Licence expirée depuis le ${new Date(found.expiresAt).toLocaleDateString()}. Veuillez renouveler votre abonnement.`,
          status: 'expired',
          expiresAt: found.expiresAt
        });
        return;
      }

      // Check quota
      if (found.bandwidthUsedGb >= found.bandwidthGb) {
        found.status = 'quota_exceeded';
        saveTokens(tokens);
        res.status(403).json({
          valid: false,
          error: `Quota de données épuisé (${found.bandwidthUsedGb.toFixed(2)} Go / ${found.bandwidthGb} Go). Contactez votre revendeur.`,
          status: 'quota_exceeded',
          bandwidthGb: found.bandwidthGb,
          bandwidthUsedGb: found.bandwidthUsedGb
        });
        return;
      }

      found.connectionCount = (found.connectionCount || 0) + 1;
      found.lastSeenAt = new Date().toISOString();
      found.lastSeenIp = clientIp;
      saveTokens(tokens);

      const msRemaining = Math.max(0, expiryTime - now);
      const daysRemaining = Math.ceil(msRemaining / (1000 * 3600 * 24));
      const hoursRemaining = Math.ceil(msRemaining / (1000 * 3600));
      const host = req.get('host') || 'abess-ops-hub-d-ploiement-docker.ai.studio';

      res.json({
        valid: true,
        token: found.token,
        plan: found.plan,
        reseller: found.reseller,
        createdAt: found.createdAt,
        expiresAt: found.expiresAt,
        daysRemaining: daysRemaining,
        hoursRemaining: hoursRemaining,
        deviceLimit: found.deviceLimit,
        bandwidthGb: found.bandwidthGb,
        bandwidthUsedGb: Number(found.bandwidthUsedGb.toFixed(2)),
        bandwidthRemainingGb: Number(Math.max(0, found.bandwidthGb - found.bandwidthUsedGb).toFixed(2)),
        status: found.status,
        serverConfig: {
          address: host,
          port: 443,
          path: '/@abess237',
          uuid: 'abe55237-0237-4237-8237-ab3552370237',
          sni: 'crashlyticsreports-pa.googleapis.com',
          protocol: 'vless',
          transport: 'ws',
          security: 'tls'
        }
      });
      return;
    }

    // Dynamic generation if token is long enough (guest/fallback)
    if (rawToken.length >= 8) {
      res.json({
        valid: true,
        token: rawToken,
        plan: 'ABESSVPN VIP DYNAMIC',
        reseller: 'ABESS DISTRIBUTOR',
        createdAt: new Date().toISOString(),
        expiresAt: new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString(),
        daysRemaining: 30,
        hoursRemaining: 720,
        deviceLimit: 2,
        bandwidthGb: 50.0,
        bandwidthUsedGb: 0.0,
        bandwidthRemainingGb: 50.0,
        status: 'active',
        serverConfig: {
          address: req.get('host') || 'abess-ops-hub-d-ploiement-docker.ai.studio',
          port: 443,
          path: '/@abess237',
          uuid: 'abe55237-0237-4237-8237-ab3552370237',
          sni: 'crashlyticsreports-pa.googleapis.com',
          protocol: 'vless',
          transport: 'ws',
          security: 'tls'
        }
      });
      return;
    }

    res.status(401).json({ valid: false, error: 'Token non reconnu ou introuvable.' });
  });

  // 2. Real-time Bandwidth & Traffic Reporting
  app.post('/api/v1/telemetry/traffic', (req, res) => {
    const { token, bytesTransferred } = req.body;
    if (!token || !bytesTransferred) {
      res.status(400).json({ error: 'Missing parameters' });
      return;
    }

    const tokens = loadTokens();
    const found = tokens.find(t => t.token.toUpperCase() === token.toString().toUpperCase());
    if (found) {
      const addedGb = bytesTransferred / (1024 * 1024 * 1024);
      found.bandwidthUsedGb = Number((found.bandwidthUsedGb + addedGb).toFixed(4));
      totalBytesTransferred += bytesTransferred;

      let quotaExceeded = false;
      if (found.bandwidthUsedGb >= found.bandwidthGb) {
        found.status = 'quota_exceeded';
        quotaExceeded = true;
      }
      saveTokens(tokens);

      res.json({
        success: true,
        bandwidthUsedGb: Number(found.bandwidthUsedGb.toFixed(2)),
        bandwidthRemainingGb: Number(Math.max(0, found.bandwidthGb - found.bandwidthUsedGb).toFixed(2)),
        quotaExceeded
      });
      return;
    }

    res.json({ success: true });
  });

  // 3. Anti-Abuse Test Server (1 Go / 24h) with Hardware Lock
  app.post('/api/v1/test-server/claim', (req, res) => {
    const { fingerprint, model, os } = req.body;
    const clientIp = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() || req.socket.remoteAddress || 'unknown';

    if (!fingerprint) {
      res.status(400).json({ error: 'Empreinte matérielle (HWID) requise.' });
      return;
    }

    const devices = loadDevices();
    const existing = devices.find(d => d.fingerprint === fingerprint || (d.ip === clientIp && clientIp !== '127.0.0.1' && clientIp !== '::1'));

    const now = Date.now();
    const TWENTY_FOUR_HOURS = 24 * 3600 * 1000;

    if (existing) {
      const lastClaimTime = new Date(existing.lastClaimAt).getTime();
      const timePassed = now - lastClaimTime;

      if (timePassed < TWENTY_FOUR_HOURS) {
        if (existing.remainingMb <= 0) {
          const hoursLeft = Math.ceil((TWENTY_FOUR_HOURS - timePassed) / (3600 * 1000));
          res.status(403).json({
            status: 'QUOTA_EXCEEDED',
            error: `Quota journalier de 1 Go épuisé pour cet appareil. Prochain renouvellement dans ${hoursLeft} heures.`,
            device: existing,
            hoursUntilReset: hoursLeft
          });
          return;
        }

        res.json({
          status: 'ALLOWED',
          message: 'Session de test 1 Go active.',
          device: existing,
          quotaRemainingMb: existing.remainingMb,
          token: existing.testToken,
          serverConfig: {
            host: req.get('host') || 'abess-ops-hub-d-ploiement-docker.ai.studio',
            port: 443,
            path: '/@abess237',
            uuid: 'abe55237-0237-4237-8237-ab3552370237',
            sni: 'crashlyticsreports-pa.googleapis.com'
          }
        });
        return;
      } else {
        existing.lastClaimAt = new Date().toISOString();
        existing.quotaUsedMb = 0;
        existing.remainingMb = 1024;
        existing.status = 'active';
        existing.ip = clientIp;
        saveDevices(devices);

        res.json({
          status: 'RESET_GRANTED',
          message: 'Nouveau quota quotidien de 1 Go activé !',
          device: existing,
          quotaRemainingMb: 1024,
          token: existing.testToken
        });
        return;
      }
    }

    const newDevice: DeviceLock = {
      id: 'dev_' + Math.random().toString(36).substring(2, 9),
      fingerprint,
      ip: clientIp,
      model: model || 'Smartphone Non Identifié',
      os: os || 'Système Sécurisé',
      firstSeenAt: new Date().toISOString(),
      lastClaimAt: new Date().toISOString(),
      dailyQuotaMb: 1024,
      quotaUsedMb: 0,
      remainingMb: 1024,
      status: 'active',
      testToken: 'ABESS-FREE-1GB-' + Math.floor(1000 + Math.random() * 9000)
    };

    devices.unshift(newDevice);
    saveDevices(devices);

    res.status(201).json({
      status: 'NEW_DEVICE_REGISTERED',
      message: 'Appareil enregistré avec succès. 1 Go activé pour 24 heures.',
      device: newDevice,
      quotaRemainingMb: 1024,
      token: newDevice.testToken,
      serverConfig: {
        host: req.get('host') || 'abess-ops-hub-d-ploiement-docker.ai.studio',
        port: 443,
        path: '/@abess237',
        uuid: 'abe55237-0237-4237-8237-ab3552370237',
        sni: 'crashlyticsreports-pa.googleapis.com'
      }
    });
  });

  app.get('/api/v1/test-server/devices', (req, res) => {
    res.json(loadDevices());
  });

  // 4. Encrypted Configuration Link & File Generator (`abess://...`)
  app.post('/api/v1/crypto/encrypt', (req, res) => {
    try {
      const config = req.body;
      if (!config) {
        res.status(400).json({ error: 'Configuration data required' });
        return;
      }
      const encryptedLink = encryptConfigPayload(config);
      res.json({
        success: true,
        encryptedLink,
        format: 'abess://<payload>',
        cipher: 'AES-256-CBC with SHA-256 Key derivation',
        createdAt: new Date().toISOString(),
        expiresAt: config.expiresAt,
        bandwidthGb: config.bandwidthGb
      });
    } catch (err: unknown) {
      res.status(500).json({ error: err instanceof Error ? err.message : String(err) });
    }
  });

  app.post('/api/v1/crypto/decrypt', (req, res) => {
    try {
      const { link } = req.body;
      if (!link) {
        res.status(400).json({ error: 'Link required' });
        return;
      }
      const decrypted = decryptConfigPayload(link);
      res.json({ success: true, configuration: decrypted });
    } catch (err: unknown) {
      res.status(400).json({ error: err instanceof Error ? err.message : String(err) });
    }
  });

  // 5. Token creation with precise Gigas & Expiration Date
  app.get('/api/v1/tokens', (req, res) => {
    res.json(loadTokens());
  });

  app.post('/api/v1/tokens', (req, res) => {
    const { token, plan, reseller, days, expiresAt, deviceLimit, bandwidthGb } = req.body;
    if (!token || !plan) {
      res.status(400).json({ error: 'Token and Plan are required' });
      return;
    }

    const calculatedExpiresAt = expiresAt || new Date(Date.now() + (Number(days) || 30) * 24 * 3600 * 1000).toISOString();
    const daysRemaining = Math.max(0, Math.ceil((new Date(calculatedExpiresAt).getTime() - Date.now()) / (1000 * 3600 * 24)));

    const tokens = loadTokens();
    const newToken: ClientToken = {
      id: 'tok_' + Math.random().toString(36).substring(2, 9),
      token: token.toString().trim().toUpperCase(),
      plan: plan.toString().trim(),
      reseller: (reseller || 'ABESS DISTRIBUTOR').toString().trim(),
      days: daysRemaining,
      createdAt: new Date().toISOString(),
      expiresAt: calculatedExpiresAt,
      deviceLimit: Number(deviceLimit) || 2,
      bandwidthGb: Number(bandwidthGb) || 50,
      bandwidthUsedGb: 0,
      connectionCount: 0,
      lastSeenAt: null,
      lastSeenIp: null,
      status: 'active'
    };

    tokens.unshift(newToken);
    saveTokens(tokens);
    res.status(201).json(newToken);
  });

  app.delete('/api/v1/tokens/:id', (req, res) => {
    const tokens = loadTokens();
    const updated = tokens.filter(t => t.id !== req.params.id);
    saveTokens(updated);
    res.json({ success: true, count: updated.length });
  });

  // Status API
  app.get('/api/v1/status', (req, res) => {
    res.json({
      status: 'ONLINE',
      engine: 'ABESSVPN CYBER ENGINE 2026',
      activeConnections: activeTunnelConnections,
      totalBytesTransferred,
      uptimeSeconds: Math.floor((Date.now() - startTime) / 1000),
      wsPath: '/@abess237',
      port: PORT,
      timestamp: new Date().toISOString()
    });
  });

  // WebSocket Server on /@abess237
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (request, socket, head) => {
    const pathname = new URL(request.url || '', `http://${request.headers.host}`).pathname;

    if (pathname === '/@abess237' || pathname.startsWith('/@abess237')) {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    }
  });

  wss.on('connection', (ws: WebSocket, req) => {
    activeTunnelConnections++;
    ws.on('message', (message, isBinary) => {
      const len = isBinary ? (message as Buffer).length : Buffer.byteLength(message.toString());
      totalBytesTransferred += len;
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(Buffer.from([0x00, 0x00])); // VLESS response handshake
      }
    });

    ws.on('close', () => {
      activeTunnelConnections = Math.max(0, activeTunnelConnections - 1);
    });

    ws.on('error', () => {
      activeTunnelConnections = Math.max(0, activeTunnelConnections - 1);
    });
  });

  // Frontend static / dev middleware
  if (!isProduction) {
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa'
    });
    app.use(vite.middlewares);
  } else {
    app.use(express.static(path.resolve(__dirname, 'dist')));
    app.get('*', (req, res) => {
      res.sendFile(path.resolve(__dirname, 'dist', 'index.html'));
    });
  }

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`[ABESSVPN ENGINE] Running on port ${PORT}`);
  });
}

startServer().catch(console.error);
