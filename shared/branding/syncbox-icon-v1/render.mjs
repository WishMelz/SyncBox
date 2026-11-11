import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const directory = new URL('./', import.meta.url);
const source = await readFile(new URL('icon.svg', directory), 'utf8');
const glyph = source.match(/<g id="syncbox-mark"[\s\S]*?<\/g>/)?.[0];
if (!glyph) throw new Error('The SVG master is missing its symbol.');

// Opaque, full-bleed master: platform launchers apply their own corner mask.
for (const size of [1024, 512, 256, 64, 32]) {
  await sharp(Buffer.from(source))
    .resize(size, size)
    .removeAlpha()
    .png()
    .toFile(fileURLToPath(new URL(`icon-${size}.png`, directory)));
}
await writeFile(new URL('mark.svg', directory),
  `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${glyph}</svg>\n`);

const roundMask = Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512"><rect width="512" height="512" rx="112" fill="white"/></svg>');
const preview = await sharp(Buffer.from(source)).resize(512, 512).ensureAlpha()
  .composite([{ input: roundMask, blend: 'dest-in' }]).png().toBuffer();
await writeFile(new URL('preview.png', directory), preview);

// A compact presentation sheet includes actual small-size renders, not scaled UI text.
const board = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="860">
  <rect width="1400" height="860" fill="#F5F8FC"/>
  <g fill="#1E2E40" font-family="Arial, sans-serif">
    <text x="720" y="278" font-size="72" font-weight="700" letter-spacing="-2">SyncBox</text>
    <text x="722" y="328" font-size="23" fill="#6D8195">Your devices. One shared space.</text>
    <path d="M722 376H1230" stroke="#DCE5EE"/>
    <text x="722" y="434" font-size="16" letter-spacing="2" fill="#8192A3">ONE MARK. EVERY DEVICE.</text>
    <text x="730" y="596" font-size="15" fill="#8192A3">96</text>
    <text x="906" y="596" font-size="15" fill="#8192A3">64</text>
    <text x="1050" y="596" font-size="15" fill="#8192A3">32</text>
    <text x="150" y="768" font-size="17" fill="#8192A3">SYNCBOX / APP ICON / V1</text>
  </g>
</svg>`);
const overlays = [{ input: await sharp(preview).resize(440, 440).toBuffer(), left: 150, top: 180 }];
for (const [size, left] of [[96, 722], [64, 898], [32, 1042]]) {
  overlays.push({ input: await sharp(preview).resize(size, size).toBuffer(), left, top: 480 + (96 - size) });
}
await sharp(board).composite(overlays).removeAlpha().png()
  .toFile(fileURLToPath(new URL('presentation.png', directory)));
console.log(`Exported SyncBox icon assets to ${fileURLToPath(directory)}`);
