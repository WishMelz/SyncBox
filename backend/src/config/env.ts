export function validateEnvironment(env: Record<string, unknown>) {
  const portText = String(env.PORT ?? '3000');
  const port = Number(portText);
  if (!/^\d+$/.test(portText) || port < 1 || port > 65535) {
    throw new Error('PORT must be an integer between 1 and 65535');
  }
  const nodeEnv = String(env.NODE_ENV ?? 'development');
  if (!['development', 'test', 'production'].includes(nodeEnv)) {
    throw new Error('NODE_ENV must be development, test, or production');
  }
  const trustProxy = String(env.TRUST_PROXY ?? 'false');
  if (!['true', 'false'].includes(trustProxy)) throw new Error('TRUST_PROXY must be true or false');
  const host = String(env.HOST ?? '127.0.0.1').trim();
  const databasePath = String(env.DATABASE_PATH ?? './data/syncbox.sqlite').trim();
  const staticDir = String(env.STATIC_DIR ?? '').trim();
  if (!host) throw new Error('HOST must not be empty');
  if (!databasePath) throw new Error('DATABASE_PATH must not be empty');
  return {
    ...env,
    TRUST_PROXY: trustProxy === 'true',
    PORT: port,
    NODE_ENV: nodeEnv,
    HOST: host,
    DATABASE_PATH: databasePath,
    STATIC_DIR: staticDir,
  };
}
