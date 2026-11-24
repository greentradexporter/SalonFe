import fs from 'node:fs/promises';
import sharp from '../admin/node_modules/sharp/lib/index.js';
const out = 'output/play-release';
await fs.mkdir(out, {recursive: true});
await sharp('assets/brand/salonfe_icon.png').resize(512, 512).png().toFile(`${out}/salonfe-icon-512.png`);
const logo = (await fs.readFile('assets/brand/salonfe_wordmark.png')).toString('base64');
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
<rect width="1024" height="500" fill="#FF7B54"/>
<circle cx="950" cy="0" r="240" fill="#ff9577"/>
<circle cx="1080" cy="460" r="280" fill="#ff6942"/>
<image href="data:image/png;base64,${logo}" x="68" y="74" width="520" height="162"/>
<text x="76" y="302" font-family="Arial, sans-serif" font-size="36" font-weight="700" fill="#000000">Your next salon visit, simplified.</text>
<rect x="76" y="350" width="218" height="60" rx="30" fill="#FFFFFF"/>
<text x="185" y="388" text-anchor="middle" font-family="Arial, sans-serif" font-size="22" font-weight="700" fill="#000000">Book a service</text>
<rect x="310" y="350" width="250" height="60" rx="30" fill="#FFFFFF"/>
<text x="435" y="388" text-anchor="middle" font-family="Arial, sans-serif" font-size="22" font-weight="700" fill="#000000">Manage your salon</text>
</svg>`;
await fs.writeFile(`${out}/feature-graphic.svg`, svg);
await sharp(Buffer.from(svg)).removeAlpha().png().toFile(`${out}/salonfe-feature-1024x500.png`);
console.log('Prepared SalonFe Play icon and feature graphic.');
