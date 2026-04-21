#!/usr/bin/env node
// Generate an Ed25519 keypair for the events-manifest signing flow (HEY1306).
//
// Output is base64(seed || publicKey) — 64 bytes total — which is the format
// MANIFEST_SIGNING_KEY expects in the CDN worker. The same value can be
// rotated at any time; only the operator (you) ever sees the seed half.
//
// Usage:
//   node scripts/generate-manifest-key.mjs            # prints to stdout
//   node scripts/generate-manifest-key.mjs | wrangler secret put MANIFEST_SIGNING_KEY

import { generateKeyPairSync } from "node:crypto";

const { publicKey, privateKey } = generateKeyPairSync("ed25519");
const pkcs8 = privateKey.export({ format: "der", type: "pkcs8" });
const spki = publicKey.export({ format: "der", type: "spki" });

// PKCS#8 for Ed25519 carries the 32-byte seed at the tail; SPKI carries the
// 32-byte public key at the tail. See RFC 8410.
const seed = pkcs8.subarray(pkcs8.length - 32);
const pub = spki.subarray(spki.length - 32);
const combined = Buffer.concat([seed, pub]);

const stdoutIsTty = process.stdout.isTTY === true;
if (stdoutIsTty) {
  process.stderr.write("MANIFEST_SIGNING_KEY (base64, 64 bytes):\n");
  process.stderr.write(`  publicKey (base64, also returned in manifest.signingKey):\n  ${pub.toString("base64")}\n\n`);
}

process.stdout.write(combined.toString("base64"));
if (stdoutIsTty) process.stdout.write("\n");
