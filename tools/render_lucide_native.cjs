// Asset generation only. Requires sharp; never launches the app or a server.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.argv[2] || 'sharp');
const root = path.resolve(__dirname, '..');
const assets = path.join(root, 'assets/icons/lucide');
const manifest = JSON.parse(fs.readFileSync(path.join(assets, 'manifest.json'), 'utf8'));

async function main() {
  for (const [assetName, iconName] of Object.entries(manifest.ios_assets)) {
    const dir = path.join(root, 'ios/Runner/Assets.xcassets', `${assetName}.imageset`);
    fs.mkdirSync(dir, { recursive: true });
    let svg = fs.readFileSync(path.join(assets, `${iconName}.svg`), 'utf8')
      .replaceAll('currentColor', '#000000');
    if (assetName.endsWith('Filled')) svg = svg.replace('fill="none"', 'fill="#000000"');
    const images = [];
    for (const scale of [1, 2, 3]) {
      const filename = `${iconName}@${scale}x.png`;
      await sharp(Buffer.from(svg)).resize(32 * scale, 32 * scale).png().toFile(path.join(dir, filename));
      images.push({ idiom: 'universal', filename, scale: `${scale}x` });
    }
    fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify({
      images,
      info: { author: 'xcode', version: 1 },
      properties: { 'template-rendering-intent': 'template' },
    }, null, 2) + '\n');
  }
  console.log(`Generated ${Object.keys(manifest.ios_assets).length} local CarPlay image sets.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
