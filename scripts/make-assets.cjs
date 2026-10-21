const fs = require('node:fs');
const sharp = require('sharp');
(async () => {
 const mark = fs.readFileSync('public/logo.svg','utf8').replace(/<svg[^>]*>/,'').replace('</svg>','');
 const icon = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" rx="112" fill="#1A1D21"/><svg x="64" y="80" width="384" height="352" viewBox="5 20 90 70" fill="none" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">${mark.replaceAll('#1A1D21','#FFFFFF')}</svg></svg>`;
 await sharp(Buffer.from(icon)).png().toFile('desktop/assets/icon.png');
 const tray = `<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="5 20 90 70" fill="none" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">${mark.replaceAll('#1A1D21','#000000').replaceAll('#F26830','#000000')}</svg>`;
 await sharp(Buffer.from(tray)).png().toFile('desktop/assets/trayTemplate.png');
})().catch(e=>{console.error(e);process.exitCode=1;});
