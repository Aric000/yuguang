const fs = require('node:fs');
const tag = process.env.RELEASE_TAG;
if (!/^v\d+\.\d+\.\d+$/.test(tag || '')) throw new Error('版本标签必须为 v主版本.次版本.修订号');
for (const filename of ['package.json','package-lock.json']) {
  const json = JSON.parse(fs.readFileSync(filename,'utf8')); json.version = tag.slice(1);
  if (json.packages?.['']) json.packages[''].version = json.version;
  fs.writeFileSync(filename, JSON.stringify(json,null,2)+'\n');
}
