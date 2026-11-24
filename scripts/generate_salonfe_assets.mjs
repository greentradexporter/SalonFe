// Deterministic crops/resizes of the supplied artwork; no generated replacement
// logo. Run with the reference directory as the first argument.
import fs from 'node:fs/promises';
import path from 'node:path';
import sharp from '../admin/node_modules/sharp/lib/index.js';

const sourceDirectory = process.argv[2];
if (!sourceDirectory) throw new Error('Pass the supplied Salonfe artwork directory.');
const brandDirectory = 'assets/brand';
const coral = '#FF7B54';
await fs.mkdir(brandDirectory, { recursive: true });
const source = path.join(sourceDirectory, '5d2f8164-d072-4589-a50d-734a52c84060.jpg');
await sharp(source).png().toFile(`${brandDirectory}/salonfe_logo.png`);
// The full supplied wordmark, with its empty square margins removed.
const wordmark = await sharp(source)
  .extract({ left: 0, top: 450, width: 1280, height: 400 })
  .resize(960, 300).png().toBuffer();
await fs.writeFile(`${brandDirectory}/salonfe_wordmark.png`, wordmark);
const wordmarkPixels = await sharp(wordmark).raw().toBuffer({ resolveWithObject: true });
const transparentWordmark = Buffer.alloc(wordmarkPixels.info.width * wordmarkPixels.info.height * 4);
for (let i = 0; i < wordmarkPixels.info.width * wordmarkPixels.info.height; i++) {
  const g = wordmarkPixels.data[i * wordmarkPixels.info.channels + 1];
  const b = wordmarkPixels.data[i * wordmarkPixels.info.channels + 2];
  transparentWordmark[i * 4] = 255;
  transparentWordmark[i * 4 + 1] = 123;
  transparentWordmark[i * 4 + 2] = 84;
  transparentWordmark[i * 4 + 3] = Math.max(0, Math.min(255, Math.round((Math.min(g, b) - 140) * 255 / 80)));
}
await sharp(transparentWordmark, { raw: { width: wordmarkPixels.info.width, height: wordmarkPixels.info.height, channels: 4 } })
  .png().toFile(`${brandDirectory}/salonfe_wordmark_coral.png`);
// Use the S from the supplied wordmark as the small, legible launcher mark.
const letter = await sharp(source)
  .extract({ left: 0, top: 490, width: 199, height: 290 })
  .raw().toBuffer({ resolveWithObject: true });
const whiteMask = Buffer.alloc(letter.info.width * letter.info.height * 4);
for (let i = 0; i < letter.info.width * letter.info.height; i++) {
  const g = letter.data[i * letter.info.channels + 1];
  const b = letter.data[i * letter.info.channels + 2];
  whiteMask[i * 4] = whiteMask[i * 4 + 1] = whiteMask[i * 4 + 2] = 255;
  whiteMask[i * 4 + 3] = Math.max(0, Math.min(255, Math.round((Math.min(g, b) - 140) * 255 / 80)));
}
const mark = await sharp(whiteMask, { raw: { width: 199, height: 290, channels: 4 } })
  .resize({ height: 620 }).png().toBuffer({ resolveWithObject: true });
const icon = await sharp({ create: { width: 1024, height: 1024, channels: 3, background: coral } })
  .composite([{ input: mark.data, left: Math.round((1024 - mark.info.width) / 2), top: 202 }])
  .png().toBuffer();
await fs.writeFile(`${brandDirectory}/salonfe_icon.png`, icon);

const densities = { mdpi: [48, 108], hdpi: [72, 162], xhdpi: [96, 216], xxhdpi: [144, 324], xxxhdpi: [192, 432] };
for (const [density, [size, foregroundSize]] of Object.entries(densities)) {
  const directory = `android/app/src/main/res/mipmap-${density}`;
  await sharp(icon).resize(size, size).toFile(`${directory}/ic_launcher.png`);
  // Adaptive foreground: the glyph is inside Android's central safe region.
  await sharp({ create: { width: foregroundSize, height: foregroundSize, channels: 4, background: '#00000000' } })
    .composite([{ input: await sharp(icon).resize(Math.round(foregroundSize * 0.65)).png().toBuffer(), gravity: 'centre' }])
    .png().toFile(`${directory}/ic_launcher_foreground.png`);
}
await sharp(wordmark).resize(240, 75).toFile('android/app/src/main/res/drawable-nodpi/launch_logo.png');
for (const [name, multiplier] of [['LaunchImage.png', 1], ['LaunchImage@2x.png', 2], ['LaunchImage@3x.png', 3]]) {
  await sharp(wordmark).resize(240 * multiplier, 75 * multiplier)
    .toFile(`ios/Runner/Assets.xcassets/LaunchImage.imageset/${name}`);
}
const iconDirectory = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const contents = JSON.parse(await fs.readFile(`${iconDirectory}/Contents.json`, 'utf8'));
for (const entry of contents.images) {
  const size = Math.round(parseFloat(entry.size) * parseFloat(entry.scale));
  await sharp(icon).resize(size, size).removeAlpha().toFile(`${iconDirectory}/${entry.filename}`);
}
for (const size of [192, 512]) {
  for (const prefix of ['Icon-', 'Icon-maskable-']) {
    await sharp(icon).resize(size, size).toFile(`web/icons/${prefix}${size}.png`);
  }
}
await sharp(icon).resize(32, 32).toFile('web/favicon.png');
// Android status-bar icons require a white silhouette with transparency.
for (const [density, size] of Object.entries({ mdpi: 24, hdpi: 36, xhdpi: 48, xxhdpi: 72, xxxhdpi: 96 })) {
  const directory = `android/app/src/main/res/drawable-${density}`;
  await fs.mkdir(directory, { recursive: true });
  await sharp(whiteMask, { raw: { width: 199, height: 290, channels: 4 } })
    .resize(size, size, { fit: 'contain', background: '#00000000' })
    .png().toFile(`${directory}/ic_stat_salonfe.png`);
}
const serviceArtwork = {
  haircut: '16B18352-CBDE-4DDF-9E75-4515A7A0353F.png',
  beard: '01DF46E3-5E56-4616-B5D4-6DD2C7A1D73F.png',
  facial: 'C584ED3B-430A-4122-ACD1-E63662ED8B5A.png',
  spa: 'C584ED3B-430A-4122-ACD1-E63662ED8B5A.png',
  mani_pedi: '5D7517A2-8524-45EB-88F9-D61FA489C34A.png',
  threading: 'F071B9F6-75E8-4874-B587-EBF34B190CEC.png',
  waxing: 'E7279A1A-627B-448A-8CD7-ACF6DB33AD6B.png',
  hair_wash: 'F2ADA6AD-E1C5-4384-A902-CBED2A073FEA.png',
  nails: '2B3621D1-9C09-4ED5-9D12-3374BDFF550E.png',
};
for (const [name, filename] of Object.entries(serviceArtwork)) {
  await sharp(path.join(sourceDirectory, filename)).resize(320, 320)
    .png().toFile(`assets/service_icons/${name}.png`);
}
console.log('Generated SalonFe logo, wordmark, platform icons, splash images, notification mark and service artwork.');
