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

// Persistent Data Storage
const dataDir = path.resolve(__dirname, 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const usersFile = path.resolve(dataDir, 'users.json');
const tokensFile = path.resolve(dataDir, 'tokens.json');
const configFile = path.resolve(dataDir, 'config.json');
const devicesFile = path.resolve(dataDir, 'devices.json');

export interface DeviceRecord {
  id: string;
  fingerprint: string;
  ip: string;
  model: string;
  os: string;
  firstSeenAt: string;
  lastClaimAt: string;
  dailyQuotaMb: number;
  quotaUsedMb: number;
  remainingMb: number;
  status: 'active' | 'blocked';
  testToken?: string;
  boundTokens?: string[];
}

// Interfaces
export interface AppUser {
  id: string;
  email: string;
  passwordHash: string; // Plain or sha256
  name: string;
  role: 'SUPER_ADMIN' | 'RESELLER';
  credits: number; // Balance in credits / GB
  totalTokensCreated: number;
  totalBandwidthAllocatedGb: number;
  status: 'active' | 'suspended';
  createdAt: string;
  lastLoginAt: string | null;
}

export interface ClientToken {
  id: string;
  token: string;
  resellerId: string;
  resellerName: string;
  plan: string;
  bandwidthGb: number;
  bandwidthUsedGb: number;
  expiresAt: string;
  days: number;
  deviceLimit: number;
  connectionCount: number;
  lastSeenAt: string | null;
  lastSeenIp: string | null;
  status: 'active' | 'revoked' | 'expired' | 'quota_exceeded';
  encryptedLink: string;
  createdAt: string;
}

export interface MasterServerConfig {
  serverHost: string;
  serverPort: number;
  protocol: string;
  transport: string;
  path: string;
  sniHost: string;
  uuid: string;
  secretPassphrase: string;
  systemName: string;
  contactTelegram: string;
}

// Master Configuration Helper
function loadMasterConfig(): MasterServerConfig {
  const defaults: MasterServerConfig = {
    serverHost: 'abess-ops-hub-d-ploiement-docker.ai.studio',
    serverPort: 443,
    protocol: 'vless',
    transport: 'ws',
    path: '/@abess237',
    sniHost: 'crashlyticsreports-pa.googleapis.com',
    uuid: 'abe55237-0237-4237-8237-ab3552370237',
    secretPassphrase: 'AbessVpn-Master-SecretKey-2026',
    systemName: 'AbessVpn Master Server',
    contactTelegram: '@abess237'
  };

  if (fs.existsSync(configFile)) {
    try {
      return { ...defaults, ...JSON.parse(fs.readFileSync(configFile, 'utf8')) };
    } catch {
      // fallback
    }
  }

  fs.writeFileSync(configFile, JSON.stringify(defaults, null, 2), 'utf8');
  return defaults;
}

function saveMasterConfig(cfg: MasterServerConfig) {
  fs.writeFileSync(configFile, JSON.stringify(cfg, null, 2), 'utf8');
}

// User Storage with Initial Super Admin
function loadUsers(): AppUser[] {
  if (fs.existsSync(usersFile)) {
    try {
      return JSON.parse(fs.readFileSync(usersFile, 'utf8'));
    } catch {
      // fallback
    }
  }

  const superAdmin: AppUser = {
    id: 'usr_admin_master',
    email: 'rigomanga4@gmail.com',
    passwordHash: 'abess237', // Master admin password as specified
    name: 'Rigobert Manga (Admin Principal)',
    role: 'SUPER_ADMIN',
    credits: 999999,
    totalTokensCreated: 12,
    totalBandwidthAllocatedGb: 600,
    status: 'active',
    createdAt: new Date().toISOString(),
    lastLoginAt: new Date().toISOString()
  };

  const sampleReseller: AppUser = {
    id: 'usr_reseller_demo',
    email: 'revendeur@abessvpn.com',
    passwordHash: 'revendeur123',
    name: 'Distributeur Cameroun VIP',
    role: 'RESELLER',
    credits: 250, // 250 Go disponibles à vendre
    totalTokensCreated: 5,
    totalBandwidthAllocatedGb: 150,
    status: 'active',
    createdAt: new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString(),
    lastLoginAt: new Date().toISOString()
  };

  const initial = [superAdmin, sampleReseller];
  fs.writeFileSync(usersFile, JSON.stringify(initial, null, 2), 'utf8');
  return initial;
}

function saveUsers(users: AppUser[]) {
  fs.writeFileSync(usersFile, JSON.stringify(users, null, 2), 'utf8');
}

// Tokens Storage
function loadTokens(): ClientToken[] {
  if (fs.existsSync(tokensFile)) {
    try {
      return JSON.parse(fs.readFileSync(tokensFile, 'utf8'));
    } catch {
      // fallback
    }
  }

  const sample: ClientToken[] = [
    {
      id: 'tok_root_1',
      token: 'ABESS-VIP-ROOT-2026',
      resellerId: 'usr_admin_master',
      resellerName: 'Rigobert Manga (Admin Principal)',
      plan: 'COMMERCE VIP ULTRA 50 GO',
      bandwidthGb: 50,
      bandwidthUsedGb: 3.42,
      expiresAt: new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString(),
      days: 30,
      deviceLimit: 2,
      connectionCount: 38,
      lastSeenAt: new Date().toISOString(),
      lastSeenIp: '197.234.221.14',
      status: 'active',
      encryptedLink: 'abess://MASTER.ENCRYPTED.PAYLOAD',
      createdAt: new Date().toISOString()
    }
  ];
  fs.writeFileSync(tokensFile, JSON.stringify(sample, null, 2), 'utf8');
  return sample;
}

function saveTokens(tokens: ClientToken[]) {
  fs.writeFileSync(tokensFile, JSON.stringify(tokens, null, 2), 'utf8');
}

// Devices Anti-Abuse Storage
function loadDevices(): DeviceRecord[] {
  if (fs.existsSync(devicesFile)) {
    try {
      return JSON.parse(fs.readFileSync(devicesFile, 'utf8'));
    } catch {
      // fallback
    }
  }
  return [];
}

function saveDevices(devices: DeviceRecord[]) {
  fs.writeFileSync(devicesFile, JSON.stringify(devices, null, 2), 'utf8');
}

// AES-256 Encryption Helper
function encryptConfig(plainJson: object, secret: string): string {
  const key = crypto.createHash('sha256').update(secret).digest();
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
  let encrypted = cipher.update(JSON.stringify(plainJson), 'utf8', 'base64');
  encrypted += cipher.final('base64');
  return `abess://${iv.toString('base64')}.${encrypted}`;
}

// Telemetry & metrics
let activeTunnelConnections = 0;
let totalBytesTransferred = 1024 * 1024 * 460;

// Sessions in memory for token authentication
const activeSessions = new Map<string, { userId: string; role: string; email: string }>();

async function startServer() {
  const app = express();

  app.use(express.json({ limit: '1mb' }));

  // Security Headers & CORS
  app.use((req, res, next) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '1; mode=block');
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

  // Authentication Middleware
  const authenticate = (req: express.Request, res: express.Response, next: express.NextFunction) => {
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Session non authentifiée. Veuillez vous connecter.' });
      return;
    }

    const token = authHeader.split(' ')[1];
    const session = activeSessions.get(token);
    if (!session) {
      res.status(401).json({ error: 'Session expirée ou invalide.' });
      return;
    }

    const users = loadUsers();
    const user = users.find(u => u.id === session.userId && u.status === 'active');
    if (!user) {
      res.status(401).json({ error: 'Compte suspendu ou introuvable.' });
      return;
    }

    (req as any).user = user;
    next();
  };

  // ==========================================
  // 1. AUTHENTICATION & LOGIN (Admin & Reseller)
  // ==========================================
  app.post('/api/v1/auth/login', (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) {
      res.status(400).json({ error: 'Email et mot de passe requis' });
      return;
    }

    const users = loadUsers();
    const user = users.find(
      u => u.email.toLowerCase().trim() === String(email).toLowerCase().trim() && u.passwordHash === password
    );

    if (!user) {
      res.status(401).json({ error: 'Identifiants incorrects (Email ou Mot de passe invalide)' });
      return;
    }

    if (user.status !== 'active') {
      res.status(403).json({ error: 'Ce compte a été suspendu par l\'administrateur principal.' });
      return;
    }

    user.lastLoginAt = new Date().toISOString();
    saveUsers(users);

    const sessionToken = 'sess_' + crypto.randomBytes(32).toString('hex');
    activeSessions.set(sessionToken, {
      userId: user.id,
      role: user.role,
      email: user.email
    });

    res.json({
      success: true,
      token: sessionToken,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
        credits: user.credits,
        totalTokensCreated: user.totalTokensCreated,
        totalBandwidthAllocatedGb: user.totalBandwidthAllocatedGb
      }
    });
  });

  app.get('/api/v1/auth/me', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    res.json({
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      credits: user.credits,
      totalTokensCreated: user.totalTokensCreated,
      totalBandwidthAllocatedGb: user.totalBandwidthAllocatedGb
    });
  });

  // ==========================================
  // 2. RESELLER MANAGEMENT (SUPER ADMIN ONLY)
  // ==========================================
  app.get('/api/v1/admin/resellers', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    if (user.role !== 'SUPER_ADMIN') {
      res.status(403).json({ error: 'Accès réservé au Super Administrateur.' });
      return;
    }

    const users = loadUsers();
    const resellers = users
      .filter(u => u.role === 'RESELLER')
      .map(({ passwordHash, ...rest }) => rest);

    res.json(resellers);
  });

  app.post('/api/v1/admin/resellers', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    if (user.role !== 'SUPER_ADMIN') {
      res.status(403).json({ error: 'Accès réservé au Super Administrateur.' });
      return;
    }

    const { email, password, name, initialCredits } = req.body;
    if (!email || !password || !name) {
      res.status(400).json({ error: 'Email, mot de passe et nom requis pour le revendeur' });
      return;
    }

    const users = loadUsers();
    if (users.some(u => u.email.toLowerCase() === String(email).toLowerCase().trim())) {
      res.status(400).json({ error: 'Un compte avec cet email existe déjà.' });
      return;
    }

    const newReseller: AppUser = {
      id: 'usr_reseller_' + Math.random().toString(36).substring(2, 9),
      email: String(email).toLowerCase().trim(),
      passwordHash: String(password),
      name: String(name).trim(),
      role: 'RESELLER',
      credits: Number(initialCredits) || 100,
      totalTokensCreated: 0,
      totalBandwidthAllocatedGb: 0,
      status: 'active',
      createdAt: new Date().toISOString(),
      lastLoginAt: null
    };

    users.push(newReseller);
    saveUsers(users);

    const { passwordHash, ...safeReseller } = newReseller;
    res.status(201).json(safeReseller);
  });

  // Credit / Recharge Reseller
  app.put('/api/v1/admin/resellers/:id/credit', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    if (user.role !== 'SUPER_ADMIN') {
      res.status(403).json({ error: 'Accès réservé au Super Administrateur.' });
      return;
    }

    const { amount } = req.body;
    if (typeof amount !== 'number') {
      res.status(400).json({ error: 'Montant de crédit numérique requis' });
      return;
    }

    const users = loadUsers();
    const reseller = users.find(u => u.id === req.params.id && u.role === 'RESELLER');
    if (!reseller) {
      res.status(404).json({ error: 'Revendeur introuvable' });
      return;
    }

    reseller.credits = Math.max(0, reseller.credits + amount);
    saveUsers(users);

    res.json({
      success: true,
      resellerId: reseller.id,
      name: reseller.name,
      newCredits: reseller.credits
    });
  });

  // Toggle Reseller Status (Active / Suspended)
  app.put('/api/v1/admin/resellers/:id/status', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    if (user.role !== 'SUPER_ADMIN') {
      res.status(403).json({ error: 'Accès réservé au Super Administrateur.' });
      return;
    }

    const { status } = req.body;
    const users = loadUsers();
    const reseller = users.find(u => u.id === req.params.id && u.role === 'RESELLER');
    if (!reseller) {
      res.status(404).json({ error: 'Revendeur introuvable' });
      return;
    }

    reseller.status = status === 'suspended' ? 'suspended' : 'active';
    saveUsers(users);

    res.json({ success: true, status: reseller.status });
  });

  // Delete Reseller
  app.delete('/api/v1/admin/resellers/:id', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    if (user.role !== 'SUPER_ADMIN') {
      res.status(403).json({ error: 'Accès réservé au Super Administrateur.' });
      return;
    }

    const users = loadUsers();
    const filtered = users.filter(u => u.id !== req.params.id || u.role !== 'RESELLER');
    saveUsers(filtered);
    res.json({ success: true });
  });

  // ==========================================
  // 3. TOKENS CREATION & MANAGEMENT
  // ==========================================
  app.get('/api/v1/admin/tokens', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    const tokens = loadTokens();

    if (user.role === 'SUPER_ADMIN') {
      res.json(tokens);
    } else {
      const myTokens = tokens.filter(t => t.resellerId === user.id);
      res.json(myTokens);
    }
  });

  // Create Client Token (Deducts credits from Reseller)
  app.post('/api/v1/admin/tokens', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    const { token, plan, bandwidthGb, expiresAt, days, deviceLimit } = req.body;

    const requestedGb = Number(bandwidthGb) || 50;

    if (user.role === 'RESELLER') {
      if (user.credits < requestedGb) {
        res.status(400).json({
          error: `Crédits insuffisants ! Votre solde actuel est de ${user.credits} Go. Vous avez demandé ${requestedGb} Go. Veuillez contacter le Super Administrateur pour recharger votre compte.`
        });
        return;
      }
    }

    const masterConfig = loadMasterConfig();
    const finalToken = (token || 'ABESS-' + Math.random().toString(36).substring(2, 9).toUpperCase()).trim();
    const calculatedExpiresAt = expiresAt || new Date(Date.now() + (Number(days) || 30) * 24 * 3600 * 1000).toISOString();
    const daysRemaining = Math.max(0, Math.ceil((new Date(calculatedExpiresAt).getTime() - Date.now()) / (1000 * 3600 * 24)));

    const encryptedPayload = {
      vpnName: 'AbessVpn',
      token: finalToken,
      bandwidthGb: requestedGb,
      expiresAt: calculatedExpiresAt,
      serverHost: masterConfig.serverHost,
      serverPort: masterConfig.serverPort,
      path: masterConfig.path,
      sniHost: masterConfig.sniHost,
      uuid: masterConfig.uuid,
      protocol: masterConfig.protocol,
      transport: masterConfig.transport
    };
    const encryptedLink = encryptConfig(encryptedPayload, masterConfig.secretPassphrase);

    const tokens = loadTokens();
    const newToken: ClientToken = {
      id: 'tok_' + Math.random().toString(36).substring(2, 9),
      token: finalToken,
      resellerId: user.id,
      resellerName: user.name,
      plan: plan || `${requestedGb} GO CYBER VIP`,
      bandwidthGb: requestedGb,
      bandwidthUsedGb: 0,
      expiresAt: calculatedExpiresAt,
      days: daysRemaining,
      deviceLimit: Number(deviceLimit) || 2,
      connectionCount: 0,
      lastSeenAt: null,
      lastSeenIp: null,
      status: 'active',
      encryptedLink,
      createdAt: new Date().toISOString()
    };

    tokens.unshift(newToken);
    saveTokens(tokens);

    const users = loadUsers();
    const currentUser = users.find(u => u.id === user.id);
    if (currentUser) {
      if (user.role === 'RESELLER') {
        currentUser.credits = Math.max(0, currentUser.credits - requestedGb);
      }
      currentUser.totalTokensCreated = (currentUser.totalTokensCreated || 0) + 1;
      currentUser.totalBandwidthAllocatedGb = (currentUser.totalBandwidthAllocatedGb || 0) + requestedGb;
      saveUsers(users);
    }

    res.status(201).json(newToken);
  });

  // Revoke / Delete Token
  app.delete('/api/v1/admin/tokens/:id', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    const tokens = loadTokens();

    const targetToken = tokens.find(t => t.id === req.params.id);
    if (!targetToken) {
      res.status(404).json({ error: 'Token introuvable' });
      return;
    }

    if (user.role !== 'SUPER_ADMIN' && targetToken.resellerId !== user.id) {
      res.status(403).json({ error: 'Vous ne pouvez révoquer que vos propres tokens clients.' });
      return;
    }

    const updated = tokens.filter(t => t.id !== req.params.id);
    saveTokens(updated);
    res.json({ success: true });
  });

  // ==========================================
  // 4. MASTER SERVER CONFIGURATION (SUPER ADMIN ONLY)
  // ==========================================
  app.get('/api/v1/admin/server-config', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    if (user.role !== 'SUPER_ADMIN') {
      res.status(403).json({ error: 'ACCÈS REFUSÉ : Les informations d\'infrastructure sont réservées au Super Administrateur.' });
      return;
    }
    res.json(loadMasterConfig());
  });

  app.put('/api/v1/admin/server-config', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    if (user.role !== 'SUPER_ADMIN') {
      res.status(403).json({ error: 'ACCÈS REFUSÉ : Seul le Super Administrateur peut modifier l\'infrastructure.' });
      return;
    }

    const current = loadMasterConfig();
    const updated = { ...current, ...req.body };
    saveMasterConfig(updated);
    res.json({ success: true, config: updated });
  });

  // ==========================================
  // 5. GLOBAL METRICS & STATS
  // ==========================================
  app.get('/api/v1/admin/stats', authenticate, (req, res) => {
    const user: AppUser = (req as any).user;
    const users = loadUsers();
    const tokens = loadTokens();

    if (user.role === 'SUPER_ADMIN') {
      const resellers = users.filter(u => u.role === 'RESELLER');
      const totalCreditsInCirculation = resellers.reduce((sum, r) => sum + r.credits, 0);
      const totalBandwidthAllocated = tokens.reduce((sum, t) => sum + t.bandwidthGb, 0);
      const totalBandwidthConsumed = tokens.reduce((sum, t) => sum + t.bandwidthUsedGb, 0);

      res.json({
        role: 'SUPER_ADMIN',
        totalResellers: resellers.length,
        totalTokens: tokens.length,
        activeTokens: tokens.filter(t => t.status === 'active').length,
        totalCreditsInCirculation,
        totalBandwidthAllocated,
        totalBandwidthConsumed: Number(totalBandwidthConsumed.toFixed(2)),
        activeTunnelConnections,
        totalBytesTransferred
      });
    } else {
      const myTokens = tokens.filter(t => t.resellerId === user.id);
      const myBandwidthAllocated = myTokens.reduce((sum, t) => sum + t.bandwidthGb, 0);
      const myBandwidthConsumed = myTokens.reduce((sum, t) => sum + t.bandwidthUsedGb, 0);

      res.json({
        role: 'RESELLER',
        creditsRemaining: user.credits,
        totalTokens: myTokens.length,
        activeTokens: myTokens.filter(t => t.status === 'active').length,
        totalBandwidthAllocated: myBandwidthAllocated,
        totalBandwidthConsumed: Number(myBandwidthConsumed.toFixed(2))
      });
    }
  });

  // ==========================================
  // 6. SPEEDTEST ENDPOINTS (DOWNLOAD & UPLOAD)
  // ==========================================
  app.get('/api/v1/speedtest/download', (req, res) => {
    const requestedBytes = Math.min(10 * 1024 * 1024, Math.max(1024, Number(req.query.bytes) || 1024 * 1024));
    const buffer = crypto.randomBytes(requestedBytes);
    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('Content-Length', requestedBytes.toString());
    res.status(200).send(buffer);
  });

  app.post('/api/v1/speedtest/upload', express.raw({ type: 'application/octet-stream', limit: '10mb' }), (req, res) => {
    const bytesReceived = req.body instanceof Buffer ? req.body.length : (typeof req.body === 'string' ? Buffer.byteLength(req.body) : 0);
    totalBytesTransferred += bytesReceived;
    res.json({ ok: true, bytesReceived, timestamp: Date.now() });
  });

  // ==========================================
  // 7. CLIENT MOBILE APPLICATION AUTHENTICATION & TELEMETRY
  // ==========================================

  // Ping Endpoint for real-time latency measurement
  app.get('/api/v1/ping', (req, res) => {
    res.json({
      ok: true,
      timestamp: Date.now(),
      server: 'AbessVpn Cyber Core v2.5',
      status: 'online',
      activeTunnels: activeTunnelConnections,
      totalBytesTransferred
    });
  });

  // Client / Reseller Token & Config Creator
  app.post('/api/v1/client/create-token', (req, res) => {
    try {
      const {
        token: customToken,
        bandwidthGb = 10,
        days = 30,
        plan = 'VIP Custom Config',
        deviceLimit = 1,
        resellerName = 'Client Direct App'
      } = req.body;

      const quotaGb = Math.max(0.5, Number(bandwidthGb) || 10);
      const durationDays = Math.max(1, Number(days) || 30);
      const devicesMax = Math.max(1, Number(deviceLimit) || 1);

      const tokens = loadTokens();
      const tokenCode = customToken && typeof customToken === 'string' && customToken.trim().length > 0
        ? customToken.trim().toUpperCase()
        : `ABESS-VIP-${Math.floor(1000 + Math.random() * 9000)}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`;

      if (tokens.some(t => t.token.toUpperCase() === tokenCode)) {
        res.status(400).json({ ok: false, error: 'Ce code token existe déjà. Veuillez en choisir un autre.' });
        return;
      }

      const now = new Date();
      const expiresAt = new Date(now.getTime() + durationDays * 24 * 3600 * 1000).toISOString();
      const masterConfig = loadMasterConfig();
      const host = masterConfig.serverHost || req.get('host') || 'abess-ops-hub-d-ploiement-docker.ai.studio';

      const payload = {
        token: tokenCode,
        server: host,
        port: masterConfig.serverPort,
        uuid: masterConfig.uuid,
        path: masterConfig.path,
        sni: masterConfig.sniHost,
        protocol: masterConfig.protocol,
        transport: masterConfig.transport,
        quotaGb,
        expiresAt,
        system: 'AbessVpn-Cyber-Core',
        deviceLimit: devicesMax
      };

      const encryptedLink = encryptConfig(payload, masterConfig.secretPassphrase);
      const vlessLink = `vless://${masterConfig.uuid}@${host}:${masterConfig.serverPort}?path=${encodeURIComponent(masterConfig.path)}&security=tls&encryption=none&type=ws&sni=${masterConfig.sniHost}#${encodeURIComponent(tokenCode + ' - ' + quotaGb + 'Go')}`;

      const newToken: ClientToken = {
        id: `tok_${crypto.randomBytes(4).toString('hex')}`,
        token: tokenCode,
        resellerId: 'app_direct',
        resellerName: String(resellerName).substring(0, 50),
        plan: String(plan).substring(0, 50),
        bandwidthGb: quotaGb,
        bandwidthUsedGb: 0.0,
        expiresAt,
        days: durationDays,
        deviceLimit: devicesMax,
        connectionCount: 0,
        lastSeenAt: null,
        lastSeenIp: null,
        status: 'active',
        encryptedLink,
        createdAt: now.toISOString()
      };

      tokens.push(newToken);
      saveTokens(tokens);

      res.json({
        ok: true,
        token: newToken.token,
        plan: newToken.plan,
        bandwidthGb: newToken.bandwidthGb,
        expiresAt: newToken.expiresAt,
        days: newToken.days,
        deviceLimit: newToken.deviceLimit,
        encryptedLink,
        vlessLink,
        serverConfig: {
          address: host,
          port: masterConfig.serverPort,
          path: masterConfig.path,
          uuid: masterConfig.uuid,
          sni: masterConfig.sniHost,
          protocol: masterConfig.protocol,
          transport: masterConfig.transport,
          security: 'tls'
        }
      });
    } catch (err: any) {
      res.status(500).json({ ok: false, error: err.message || 'Erreur lors de la création du token' });
    }
  });

  // Client Real-Time Telemetry & Quota Sync
  app.post('/api/v1/client/telemetry', (req, res) => {
    const rawToken = req.body?.token?.toString()?.trim();
    if (!rawToken) {
      res.status(400).json({ ok: false, error: 'Token manquant' });
      return;
    }
    const bytesDown = Number(req.body.bytesDownloaded) || 0;
    const bytesUp = Number(req.body.bytesUploaded) || 0;
    const totalBytes = bytesDown + bytesUp;
    const addedGb = totalBytes / (1024 * 1024 * 1024);

    const tokens = loadTokens();
    const found = tokens.find(t => t.token.toUpperCase() === rawToken.toUpperCase());
    if (!found) {
      res.status(404).json({ ok: false, error: 'Token introuvable' });
      return;
    }

    if (addedGb > 0) {
      found.bandwidthUsedGb = Number((found.bandwidthUsedGb + addedGb).toFixed(4));
      totalBytesTransferred += totalBytes;
    }
    found.lastSeenAt = new Date().toISOString();

    const now = Date.now();
    const isExpired = now > new Date(found.expiresAt).getTime();
    const isQuotaExceeded = found.bandwidthUsedGb >= found.bandwidthGb;

    if (isExpired) {
      found.status = 'expired';
    } else if (isQuotaExceeded) {
      found.status = 'quota_exceeded';
    }

    saveTokens(tokens);

    res.json({
      ok: !isExpired && !isQuotaExceeded,
      valid: !isExpired && !isQuotaExceeded,
      status: found.status,
      bandwidthGb: found.bandwidthGb,
      bandwidthUsedGb: Number(found.bandwidthUsedGb.toFixed(2)),
      bandwidthRemainingGb: Number(Math.max(0, found.bandwidthGb - found.bandwidthUsedGb).toFixed(2)),
      expiresAt: found.expiresAt,
      isExpired,
      isQuotaExceeded
    });
  });

  // Automatic 1GB / 24h Free Trial Device Anti-Abuse
  app.post('/api/v1/client/claim-free-trial', (req, res) => {
    const deviceFingerprint = req.body?.deviceId?.toString()?.trim() || req.body?.fingerprint?.toString()?.trim();
    if (!deviceFingerprint) {
      res.status(400).json({ ok: false, error: 'Identifiant matériel du téléphone (Device ID) requis' });
      return;
    }

    const devices = loadDevices();
    const clientIp = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() || req.socket.remoteAddress || 'unknown';
    const now = new Date();
    const existing = devices.find(d => d.fingerprint === deviceFingerprint);

    if (existing) {
      const lastClaim = new Date(existing.lastClaimAt).getTime();
      const elapsedHours = (now.getTime() - lastClaim) / (1000 * 3600);
      if (elapsedHours < 24) {
        const remainingHours = Math.ceil(24 - elapsedHours);
        res.status(429).json({
          ok: false,
          error: `Essai 1 Go déjà réclamé aujourd'hui sur ce téléphone. Prochain essai disponible dans ${remainingHours} heure(s).`,
          remainingHours,
          nextAvailableAt: new Date(lastClaim + 24 * 3600 * 1000).toISOString()
        });
        return;
      }
      existing.lastClaimAt = now.toISOString();
      existing.ip = clientIp;
      existing.quotaUsedMb = 0;
      existing.remainingMb = 1024;
    } else {
      const newDev: DeviceRecord = {
        id: `dev_${crypto.randomBytes(3).toString('hex')}`,
        fingerprint: deviceFingerprint,
        ip: clientIp,
        model: req.body?.model || 'Smartphone Client',
        os: req.body?.os || 'Android',
        firstSeenAt: now.toISOString(),
        lastClaimAt: now.toISOString(),
        dailyQuotaMb: 1024,
        quotaUsedMb: 0,
        remainingMb: 1024,
        status: 'active'
      };
      devices.push(newDev);
    }
    saveDevices(devices);

    const tokens = loadTokens();
    const trialTokenCode = `ABESS-FREE-1GB-${Math.floor(1000 + Math.random() * 9000)}`;
    const expiresAt = new Date(now.getTime() + 24 * 3600 * 1000).toISOString();
    const masterConfig = loadMasterConfig();
    const host = masterConfig.serverHost || req.get('host') || 'abess-ops-hub-d-ploiement-docker.ai.studio';

    const payload = {
      token: trialTokenCode,
      server: host,
      port: masterConfig.serverPort,
      uuid: masterConfig.uuid,
      path: masterConfig.path,
      sni: masterConfig.sniHost,
      protocol: masterConfig.protocol,
      transport: masterConfig.transport,
      quotaGb: 1.0,
      expiresAt,
      deviceFingerprint,
      system: 'AbessVpn-Free-Trial'
    };

    const encryptedLink = encryptConfig(payload, masterConfig.secretPassphrase);

    const trialToken: ClientToken = {
      id: `tok_${crypto.randomBytes(4).toString('hex')}`,
      token: trialTokenCode,
      resellerId: 'auto_trial',
      resellerName: 'Essai Automatique 1 Go',
      plan: 'PASS DÉCOUVERTE 1 GO / 24H',
      bandwidthGb: 1.0,
      bandwidthUsedGb: 0.0,
      expiresAt,
      days: 1,
      deviceLimit: 1,
      connectionCount: 0,
      lastSeenAt: now.toISOString(),
      lastSeenIp: clientIp,
      status: 'active',
      encryptedLink,
      createdAt: now.toISOString()
    };

    tokens.push(trialToken);
    saveTokens(tokens);

    res.json({
      ok: true,
      token: trialToken.token,
      plan: trialToken.plan,
      bandwidthGb: trialToken.bandwidthGb,
      expiresAt: trialToken.expiresAt,
      daysRemaining: 1,
      encryptedLink,
      serverConfig: {
        address: host,
        port: masterConfig.serverPort,
        path: masterConfig.path,
        uuid: masterConfig.uuid,
        sni: masterConfig.sniHost,
        protocol: masterConfig.protocol,
        transport: masterConfig.transport,
        security: 'tls'
      }
    });
  });

  // Client Token Verification & Core Configuration Delivery
  app.post('/api/v1/auth/token', (req, res) => {
    const rawToken = req.body?.token?.toString()?.trim();
    const deviceId = req.body?.deviceId?.toString()?.trim();
    if (!rawToken) {
      res.status(400).json({ valid: false, error: 'Token manquant' });
      return;
    }

    const tokens = loadTokens();
    const found = tokens.find(t => t.token.toUpperCase() === rawToken.toUpperCase());
    const clientIp = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() || req.socket.remoteAddress || 'unknown';

    if (found) {
      const now = Date.now();
      const expiryTime = new Date(found.expiresAt).getTime();

      if (now > expiryTime) {
        found.status = 'expired';
        saveTokens(tokens);
        res.status(403).json({
          valid: false,
          error: `Licence expirée le ${new Date(found.expiresAt).toLocaleDateString()}. Veuillez contacter votre revendeur.`,
          status: 'expired'
        });
        return;
      }

      if (found.bandwidthUsedGb >= found.bandwidthGb) {
        found.status = 'quota_exceeded';
        saveTokens(tokens);
        res.status(403).json({
          valid: false,
          error: `Quota de données épuisé (${found.bandwidthUsedGb.toFixed(2)} Go / ${found.bandwidthGb} Go).`,
          status: 'quota_exceeded'
        });
        return;
      }

      if (deviceId) {
        const devices = loadDevices();
        let dev = devices.find(d => d.fingerprint === deviceId);
        if (!dev) {
          dev = {
            id: `dev_${crypto.randomBytes(3).toString('hex')}`,
            fingerprint: deviceId,
            ip: clientIp,
            model: req.body?.model || 'Client Phone',
            os: req.body?.os || 'Android',
            firstSeenAt: new Date().toISOString(),
            lastClaimAt: new Date().toISOString(),
            dailyQuotaMb: 1024,
            quotaUsedMb: 0,
            remainingMb: 1024,
            status: 'active',
            boundTokens: [found.token]
          };
          devices.push(dev);
          saveDevices(devices);
        } else {
          dev.boundTokens = dev.boundTokens || [];
          if (!dev.boundTokens.includes(found.token)) {
            const boundCount = devices.filter(d => d.boundTokens && d.boundTokens.includes(found.token)).length;
            if (boundCount >= found.deviceLimit) {
              res.status(403).json({
                valid: false,
                error: `Limite d'appareils atteinte: ce token est déjà actif sur ${boundCount} appareil(s) (Maximum: ${found.deviceLimit}).`,
                status: 'device_limit_exceeded'
              });
              return;
            }
            dev.boundTokens.push(found.token);
            saveDevices(devices);
          }
        }
      }

      found.connectionCount = (found.connectionCount || 0) + 1;
      found.lastSeenAt = new Date().toISOString();
      found.lastSeenIp = clientIp;
      saveTokens(tokens);

      const masterConfig = loadMasterConfig();
      const host = masterConfig.serverHost || req.get('host') || 'abess-ops-hub-d-ploiement-docker.ai.studio';
      const msRemaining = Math.max(0, expiryTime - now);
      const daysRemaining = Math.ceil(msRemaining / (1000 * 3600 * 24));

      res.json({
        valid: true,
        token: found.token,
        plan: found.plan,
        reseller: found.resellerName,
        expiresAt: found.expiresAt,
        daysRemaining,
        deviceLimit: found.deviceLimit,
        bandwidthGb: found.bandwidthGb,
        bandwidthUsedGb: Number(found.bandwidthUsedGb.toFixed(2)),
        bandwidthRemainingGb: Number(Math.max(0, found.bandwidthGb - found.bandwidthUsedGb).toFixed(2)),
        status: found.status,
        serverConfig: {
          address: host,
          port: masterConfig.serverPort,
          path: masterConfig.path,
          uuid: masterConfig.uuid,
          sni: masterConfig.sniHost,
          protocol: masterConfig.protocol,
          transport: masterConfig.transport,
          security: 'tls'
        }
      });
      return;
    }

    res.status(401).json({ valid: false, error: 'Token client non reconnu ou révoqué.' });
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

  wss.on('connection', (ws: WebSocket) => {
    activeTunnelConnections++;
    ws.on('message', (message, isBinary) => {
      const len = isBinary ? (message as Buffer).length : Buffer.byteLength(message.toString());
      totalBytesTransferred += len;
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(Buffer.from([0x00, 0x00])); // VLESS handshake response
      }
    });

    ws.on('close', () => {
      activeTunnelConnections = Math.max(0, activeTunnelConnections - 1);
    });

    ws.on('error', () => {
      activeTunnelConnections = Math.max(0, activeTunnelConnections - 1);
    });
  });

  // Frontend static / dev middleware with safe try-catch
  if (!isProduction) {
    try {
      const { createServer: createViteServer } = await import('vite');
      const vite = await createViteServer({
        server: { middlewareMode: true },
        appType: 'spa'
      });
      app.use(vite.middlewares);
    } catch (_) {
      // Fallback if Vite is not available
    }
  } else {
    const distPath = path.resolve(__dirname, 'dist');
    if (fs.existsSync(distPath)) {
      app.use(express.static(distPath));
      app.get('*', (req, res) => {
        res.sendFile(path.resolve(distPath, 'index.html'));
      });
    }
  }

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`[ABESSVPN MASTER SERVER] Running on port ${PORT}`);
    console.log(`[ABESSVPN MASTER SERVER] Super Admin: rigomanga4@gmail.com`);
  });
}

startServer().catch(console.error);
