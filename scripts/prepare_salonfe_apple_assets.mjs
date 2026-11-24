import fs from 'node:fs/promises';
import sharp from '../admin/node_modules/sharp/lib/index.js';
const directory = 'output/apple-release';
for (const [device,width,height] of [['iphone',1320,2868],['iphone-medium',1206,2622],['ipad',2064,2752]]) {
  for (const preview of ['welcome','customer-home','owner-dashboard','owner-bookings','owner-shop','owner-balance']) {
    const input = `${directory}/${device}-${preview}-source.png`;
    await sharp(input).resize(width,height).flatten({background:'#ffffff'}).removeAlpha().png().toFile(`${directory}/${device}-${preview}.png`);
  }
}
console.log('Prepared six current iOS screenshots each for iPhone and iPad, without transparency.');
