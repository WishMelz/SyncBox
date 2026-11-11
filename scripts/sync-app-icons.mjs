import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import sharp from 'sharp';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = await readFile(resolve(root, 'shared/branding/syncbox-icon-v1/icon.svg'), 'utf8');
const mark = source.match(/<g id="syncbox-mark"[\s\S]*?<\/g>/)?.[0];
if (!mark) throw new Error('Missing SyncBox symbol in the SVG master');
const symbol = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${mark}</svg>`;
// Adaptive layers are 108 dp with a 72 dp visible face. This inset preserves
// the master symbol's optical size and leaves room for launcher motion/masks.
const adaptiveSymbol = symbol.replace(
  mark,
  `<g transform="translate(512 512) scale(0.66666667) translate(-512 -512)">${mark}</g>`,
);
const background = source.replace(mark, '');
const raster = (svg, size) => sharp(Buffer.from(svg)).resize(size, size).png().toBuffer();
async function save(path, data) {
  const destination = resolve(root, path);
  await mkdir(dirname(destination), { recursive: true });
  await writeFile(destination, data);
}
async function rounded(size, circle = false) {
  const mask = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}"><rect width="${size}" height="${size}" rx="${circle ? size / 2 : size * 0.21875}" fill="white"/></svg>`;
  return sharp(await raster(source, size))
    .ensureAlpha()
    .composite([{ input: Buffer.from(mask), blend: 'dest-in' }])
    .png()
    .toBuffer();
}
async function ico(sizes) {
  const images = await Promise.all(sizes.map((size) => rounded(size)));
  const header = Buffer.alloc(6 + 16 * images.length);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(images.length, 4);
  let offset = header.length;
  for (let n = 0; n < images.length; n++) {
    const entry = 6 + n * 16;
    header[entry] = header[entry + 1] = sizes[n] === 256 ? 0 : sizes[n];
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(images[n].length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += images[n].length;
  }
  return Buffer.concat([header, ...images]);
}

// Web: browser tabs, home screen shortcuts and visible app branding.
await save('frontend/web/public/brand/syncbox-icon.svg', source);
await save('frontend/web/public/favicon.ico', await ico([16, 32, 48]));
for (const size of [180, 192, 512]) {
  await save(`frontend/web/public/brand/icon-${size}.png`, await raster(source, size));
}

// Android: legacy launchers, round launchers, adaptive layers and themed icons.
const android = 'frontend/flutter/android/app/src/main/res';
for (const [density, size, layer] of [
  ['mdpi', 48, 108],
  ['hdpi', 72, 162],
  ['xhdpi', 96, 216],
  ['xxhdpi', 144, 324],
  ['xxxhdpi', 192, 432],
]) {
  await save(`${android}/mipmap-${density}/ic_launcher.png`, await rounded(size));
  await save(`${android}/mipmap-${density}/ic_launcher_round.png`, await rounded(size, true));
  await save(
    `${android}/drawable-${density}/ic_launcher_foreground.png`,
    await raster(adaptiveSymbol, layer),
  );
  await save(
    `${android}/drawable-${density}/ic_launcher_background.png`,
    await raster(background, layer),
  );
}
const adaptive = (themed) => `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />${themed ? '\n    <monochrome android:drawable="@drawable/ic_launcher_foreground" />' : ''}
</adaptive-icon>
`;
for (const [version, themed] of [
  ['v26', false],
  ['v33', true],
]) {
  for (const name of ['ic_launcher', 'ic_launcher_round']) {
    await save(`${android}/mipmap-anydpi-${version}/${name}.xml`, adaptive(themed));
  }
}
await save('frontend/flutter/assets/branding/syncbox-icon.png', await rounded(512));

// Windows: one ICO contains crisp native sizes from taskbar to Explorer.
await save(
  'frontend/flutter/windows/runner/resources/app_icon.ico',
  await ico([16, 24, 32, 48, 64, 128, 256]),
);

// Apple: iOS uses an opaque square; macOS uses transparent optical margins.
const apple = 'frontend/apple/SyncBox/Assets.xcassets';
const images = [
  { idiom: 'universal', platform: 'ios', size: '1024x1024', filename: 'AppIcon-ios.png' },
];
await save(
  `${apple}/AppIcon.appiconset/AppIcon-ios.png`,
  await sharp(await raster(source, 1024))
    .removeAlpha()
    .png()
    .toBuffer(),
);
const macShadow = Buffer.from(
  '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"><defs><filter id="s" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur stdDeviation="10"/></filter></defs><rect x="100" y="113" width="824" height="824" rx="180" fill="#102E52" opacity="0.18" filter="url(#s)"/></svg>',
);
const macMaster = await sharp({
  create: { width: 1024, height: 1024, channels: 4, background: '#00000000' },
})
  .composite([{ input: macShadow }, { input: await rounded(824), left: 100, top: 100 }])
  .png()
  .toBuffer();
for (const points of [16, 32, 128, 256, 512]) {
  for (const scale of [1, 2]) {
    const filename = `AppIcon-mac-${points}@${scale}x.png`;
    images.push({ idiom: 'mac', size: `${points}x${points}`, scale: `${scale}x`, filename });
    await save(
      `${apple}/AppIcon.appiconset/${filename}`,
      await sharp(macMaster)
        .resize(points * scale)
        .png()
        .toBuffer(),
    );
  }
}
await save(
  `${apple}/AppIcon.appiconset/Contents.json`,
  `${JSON.stringify({ images, info: { author: 'xcode', version: 1 } }, null, 2)}\n`,
);
await save(`${apple}/BrandIcon.imageset/brand-icon.png`, await rounded(512));
await save(
  `${apple}/BrandIcon.imageset/Contents.json`,
  `${JSON.stringify({ images: [{ idiom: 'universal', filename: 'brand-icon.png' }], info: { author: 'xcode', version: 1 } }, null, 2)}\n`,
);
// Preview the actual platform masks, including Android's adaptive viewport.
const androidComposite = await sharp(await raster(background, 360))
  .composite([{ input: await raster(adaptiveSymbol, 360) }])
  .png()
  .toBuffer();
const androidPreview = await sharp(androidComposite)
  .extract({ left: 60, top: 60, width: 240, height: 240 })
  .composite([
    {
      input: Buffer.from(
        '<svg xmlns="http://www.w3.org/2000/svg" width="240" height="240"><circle cx="120" cy="120" r="120" fill="white"/></svg>',
      ),
      blend: 'dest-in',
    },
  ])
  .png()
  .toBuffer();
const board = Buffer.from(
  '<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="460"><rect width="1280" height="460" fill="#F1F4F8"/><g fill="#506070" font-family="Arial" font-size="20"><text x="95" y="390">iOS / iPadOS</text><text x="415" y="390">Android</text><text x="725" y="390">macOS</text><text x="1025" y="390">Windows</text></g></svg>',
);
const preview = await sharp(board)
  .composite([
    { input: await rounded(240), left: 60, top: 80 },
    { input: androidPreview, left: 370, top: 80 },
    { input: await sharp(macMaster).resize(280, 280).toBuffer(), left: 660, top: 60 },
    { input: await rounded(240), left: 990, top: 80 },
  ])
  .png()
  .toBuffer();
await save('shared/branding/syncbox-icon-v1/platform-preview.png', preview);
console.log('Synced SyncBox icons: Web, Android, Windows, iOS/iPadOS and macOS.');
