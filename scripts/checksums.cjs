const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const files = fs.readdirSync('release').filter(f => /\.(dmg|zip|exe)$/.test(f));
if (!files.length) throw new Error('没有找到安装包');
for (const file of files) {
 const hash = createHash('sha256').update(fs.readFileSync(path.join('release',file))).digest('hex');
 fs.writeFileSync(path.join('release',`${file}.sha256`),`${hash}  ${file}\n`);
}
