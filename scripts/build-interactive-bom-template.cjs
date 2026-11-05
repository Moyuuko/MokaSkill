// Assemble the pinned InteractiveHtmlBom web assets for runtime use by SKILL.
const fs = require('fs');
const path = require('path');
const base = path.join(__dirname, '..', 'src', 'interactive-bom');
const web = path.join(base, 'upstream-web');
let template = fs.readFileSync(path.join(web, 'ibom.html'), 'utf8');
const assets = {
  CSS: 'ibom.css', SPLITJS: 'split.js', 'LZ-STRING': 'lz-string.js',
  POINTER_EVENTS_POLYFILL: 'pep.js', UTILJS: 'util.js', RENDERJS: 'render.js',
  TABLEUTILJS: 'table-util.js', IBOMJS: 'ibom.js'
};
for (const [marker, file] of Object.entries(assets)) {
  const content = fs.readFileSync(path.join(web, file), 'utf8');
  if (/<\/script/i.test(content)) throw new Error(`Unsafe script terminator in ${file}`);
  template = template.replace(`///${marker}///`, () => content);
}
for (const marker of ['USERCSS', 'USERJS', 'USERHEADER', 'USERFOOTER', 'CONFIG']) {
  template = template.replace(`///${marker}///`, '');
}
const bootstrap = fs.readFileSync(path.join(base, 'upstream-bootstrap.js'), 'utf8');
template = template.replace('///PCBDATA///', () => `/*__BOARD_DATA__*/\n${bootstrap}`);
if (/^\/\/\/[A-Z-]+\/\/\/$/m.test(template)) throw new Error('Unreplaced template marker');
fs.writeFileSync(path.join(base, 'upstream_template.html'), template);
