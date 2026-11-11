// Deliberately exclude storage, viewport/zoom, browser version and private-mode detection.
// The same observable environment can therefore match across normal/private windows.
// This is a best-effort fingerprint, not proof of a unique physical device.
export function deviceFingerprint(): string {
  let gpu = 'unavailable';
  try {
    const canvas = document.createElement('canvas');
    const gl = canvas.getContext('webgl');
    if (gl) {
      try {
        const info = gl.getExtension('WEBGL_debug_renderer_info');
        if (info) {
          gpu = [
            gl.getParameter(info.UNMASKED_VENDOR_WEBGL),
            gl.getParameter(info.UNMASKED_RENDERER_WEBGL),
          ]
            .map((v) => String(v).slice(0, 120))
            .join('|');
        }
      } finally {
        gl.getExtension('WEBGL_lose_context')?.loseContext();
      }
    }
  } catch {
    // WebGL may be disabled or masked by browser privacy settings.
  }
  return JSON.stringify({
    version: 2,
    platform: navigator.platform.slice(0, 80),
    agent: navigator.userAgent.replace(/\d+(?:[._]\d+)*/g, '#').slice(0, 240),
    language: (navigator.languages?.[0] ?? navigator.language ?? '').slice(0, 30),
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    touch: navigator.maxTouchPoints ?? 0,
    cores: navigator.hardwareConcurrency ?? 0,
    screen: [screen.width, screen.height].sort((a, b) => a - b),
    colorDepth: screen.colorDepth,
    gpu,
  });
}

// The cached ID is only a hint for upgrading an old device record. Fingerprint matching
// on the server is authoritative and works when this cache is empty or unavailable.
export function cachedDeviceId(userId: string): string | undefined {
  try {
    return localStorage.getItem(`syncbox-device-${userId}`) ?? undefined;
  } catch {
    return undefined;
  }
}
export function cacheDeviceId(userId: string, id: string): void {
  try {
    localStorage.setItem(`syncbox-device-${userId}`, id);
  } catch {
    // Device registration does not require persistent browser storage.
  }
}
