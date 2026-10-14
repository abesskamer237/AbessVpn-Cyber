import express from 'express';
import http from 'http';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { spawn, ChildProcess } from 'child_process';
import httpProxy from 'http-proxy';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initialisation du stockage des tokens
const dataDir = path.resolve(__dirname, 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}
const tokensFile = path.resolve(dataDir, 'tokens.json');

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
  bandwidthUsedGb?: number;
  connectionCount?: number;
  lastSeenAt?: string | null;
  lastSeenIp?: string | null;
  status: 'active' | 'revoked' | 'expired';
}

export function getTokensList(): ClientToken[] {
  if (fs.existsSync(tokensFile)) {
    try {
      return JSON.parse(fs.readFileSync(tokensFile, 'utf8'));
    } catch {
      return [];
    }
  }
  const defaults: ClientToken[] = [
    {
      id: 'tok_admin_root',
      token: 'ABESS-VIP-ROOT-2026',
      plan: 'ADMINISTRATOR UNLIMITED',
      reseller: 'SUPER ADMIN',
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString(),
      days: 365,
      deviceLimit: 10,
      bandwidthGb: 9999,
      bandwidthUsedGb: 14.8,
      connectionCount: 42,
      lastSeenAt: new Date().toISOString(),
      lastSeenIp: '127.0.0.1',
      status: 'active'
    },
    {
      id: 'tok_demo',
      token: 'ABESS-VIP-DEMO-2026',
      plan: 'COMMERCE PRO 30J',
      reseller: 'ABESS DISTRIBUTOR',
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString(),
      days: 30,
      deviceLimit: 2,
      bandwidthGb: 100,
      bandwidthUsedGb: 3.2,
      connectionCount: 15,
      lastSeenAt: new Date(Date.now() - 3600 * 1000).toISOString(),
      lastSeenIp: '192.168.1.45',
      status: 'active'
    }
  ];
  fs.writeFileSync(tokensFile, JSON.stringify(defaults, null, 2), 'utf8');
  return defaults;
}
