import {
  createHmac,
  randomBytes,
  timingSafeEqual,
  createCipheriv,
  createDecipheriv,
  scrypt,
  createHash,
} from 'node:crypto';
import { promisify } from 'node:util';
const derive = promisify(scrypt);
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
export function newSecret() {
  const bytes = randomBytes(20);
  let bits = '';
  for (const byte of bytes) bits += byte.toString(2).padStart(8, '0');
  return bits
    .match(/.{5}/g)!
    .map((part) => alphabet[parseInt(part, 2)])
    .join('');
}
export function totp(secret: string, counter: number) {
  const bits = [...secret].map((c) => alphabet.indexOf(c).toString(2).padStart(5, '0')).join('');
  const key = Buffer.from(bits.match(/.{8}/g)!.map((part) => parseInt(part, 2)));
  const moving = Buffer.alloc(8);
  moving.writeBigUInt64BE(BigInt(counter));
  const hash = createHmac('sha1', key).update(moving).digest();
  const offset = hash[hash.length - 1]! & 15;
  return ((hash.readUInt32BE(offset) & 0x7fffffff) % 1000000).toString().padStart(6, '0');
}
export function matchCounter(secret: string, code: string, last: number, now = Date.now()) {
  if (!/^\d{6}$/.test(code)) return null;
  const current = Math.floor(now / 30000);
  for (const counter of [current, current - 1, current + 1]) {
    if (counter > last && timingSafeEqual(Buffer.from(totp(secret, counter)), Buffer.from(code)))
      return counter;
  }
  return null;
}
export const recoveryHash = (code: string) =>
  createHash('sha256').update(code.trim().toLowerCase().replace(/-/g, '')).digest('hex');
// Secrets are encrypted with a key derived from the owner's password; the key is never persisted.
export async function sealSecret(secret: string, password: string) {
  const salt = randomBytes(16),
    iv = randomBytes(12);
  const key = (await derive(password, salt, 32)) as Buffer;
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const data = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
  return [salt, iv, cipher.getAuthTag(), data].map((b) => b.toString('hex')).join(':');
}
export async function openSecret(value: string, password: string) {
  const [salt, iv, tag, data] = value.split(':').map((v) => Buffer.from(v, 'hex'));
  const key = (await derive(password, salt!, 32)) as Buffer;
  const cipher = createDecipheriv('aes-256-gcm', key, iv!);
  cipher.setAuthTag(tag!);
  return Buffer.concat([cipher.update(data!), cipher.final()]).toString('utf8');
}
