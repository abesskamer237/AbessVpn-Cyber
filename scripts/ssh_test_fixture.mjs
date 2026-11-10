// Test peer for the Dart SSH client. Never used in deployment.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import http from "node:http";
import https from "node:https";
import net from "node:net";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
const require = createRequire(
  path.join(process.env.ABESS_SSH_TEST_NODE_DIR, "package.json"),
);
const { Server, utils } = require("ssh2");
const { WebSocketServer, createWebSocketStream } = require("ws");
const directory = process.argv[2];
const key = crypto.generateKeyPairSync("rsa", {
  modulusLength: 2048,
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
}).privateKey;
const fingerprint =
  "SHA256:" +
  crypto
    .createHash("sha256")
    .update(utils.parseKey(key).getPublicSSH())
    .digest("base64")
    .replace(/=+$/, "");
const password = crypto.randomBytes(18).toString("base64url");
const target = http.createServer((_req, res) =>
  res.end("ABESS_DART_SSH_REAL_TRAFFIC"),
);
await new Promise((r) => target.listen(0, "127.0.0.1", r));
const dnsTarget = net.createServer((socket) => {
  let buffer = Buffer.alloc(0);
  socket.on("error", () => {});
  socket.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    if (buffer.length < 2 || buffer.length < buffer.readUInt16BE(0) + 2) return;
    const query = buffer.subarray(2, 2 + buffer.readUInt16BE(0));
    // The fixture accepts only our test question, not arbitrary DNS traffic.
    const name = Buffer.from([
      7,
      ...Buffer.from("example"),
      3,
      ...Buffer.from("com"),
      0,
      0,
      1,
      0,
      1,
    ]);
    if (!query.subarray(12).equals(name)) {
      socket.destroy();
      return;
    }
    const header = Buffer.from([
      query[0],
      query[1],
      0x81,
      0x80,
      0,
      1,
      0,
      1,
      0,
      0,
      0,
      0,
    ]);
    const answer = Buffer.from([
      0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 1, 2, 3, 4,
    ]);
    const reply = Buffer.concat([header, name, answer]);
    const length = Buffer.alloc(2);
    length.writeUInt16BE(reply.length);
    socket.end(Buffer.concat([length, reply]));
  });
});
await new Promise((r) => dnsTarget.listen(0, "127.0.0.1", r));
const handler = (client) => {
  client.on("error", () => {});
  client.on("authentication", (ctx) =>
    ctx.method === "password" &&
    ctx.username === "ssh_test" &&
    ctx.password === password
      ? ctx.accept()
      : ctx.reject(),
  );
  client.on("ready", () =>
    client.on("tcpip", (accept, reject, info) => {
      const dns = info.destIP === "1.1.1.1" && info.destPort === 53;
      if (
        !dns &&
        (info.destIP !== "127.0.0.1" || info.destPort !== target.address().port)
      )
        return reject();
      const socket = net.connect(
        dns ? dnsTarget.address().port : target.address().port,
        "127.0.0.1",
      );
      socket.on("error", reject);
      socket.once("connect", () => {
        const channel = accept();
        channel.on("error", () => socket.destroy());
        channel.pipe(socket).pipe(channel);
      });
    }),
  );
};
const ssh = new Server({ hostKeys: [key] }, handler);
await new Promise((r) => ssh.listen(0, "127.0.0.1", r));
const tlsKey = path.join(directory, "tls.key");
const cert = path.join(directory, "tls.crt");
execFileSync(
  "openssl",
  [
    "req",
    "-x509",
    "-newkey",
    "rsa:2048",
    "-keyout",
    tlsKey,
    "-out",
    cert,
    "-days",
    "1",
    "-nodes",
    "-subj",
    "/CN=localhost",
    "-addext",
    "subjectAltName=DNS:localhost,IP:127.0.0.1",
  ],
  { stdio: "ignore" },
);
const ws = new WebSocketServer({ noServer: true });
const sshWs = new Server({ hostKeys: [key] }, handler);
const tls = https.createServer(
  { key: fs.readFileSync(tlsKey), cert: fs.readFileSync(cert) },
  (_req, res) => res.end(),
);
tls.on("tlsClientError", () => {});
tls.on("upgrade", (req, socket, head) => {
  if (req.url !== "/ws-ssh") {
    socket.destroy();
    return;
  }
  ws.handleUpgrade(req, socket, head, (connection) => {
    const stream = createWebSocketStream(connection);
    stream.remoteAddress = socket.remoteAddress;
    sshWs.injectSocket(stream);
  });
});
await new Promise((r) => tls.listen(0, "127.0.0.1", r));
fs.writeFileSync(
  path.join(directory, "fixture.json"),
  JSON.stringify({
    format: "abess-ssh-v1",
    protocol: "ssh",
    host: "127.0.0.1",
    port: ssh.address().port,
    tlsPort: tls.address().port,
    username: "ssh_test",
    password,
    fingerprint,
    transport: "tcp",
    expiresAt: new Date(Date.now() + 3600000).toISOString(),
    quotaGb: 1,
    targetPort: target.address().port,
  }),
  { mode: 0o600 },
);
console.log("SSH fixture ready");
