const fs = require('fs');
const os = require('os');
const path = require('path');
const { pathToFileURL } = require('url');
const { chromium } = require('playwright');

async function main() {
  const template = fs.readFileSync('src/interactive-bom/upstream_template.html', 'utf8');
  const footprint = (ref, layer, x) => ({ ref, center: [x, 20], layer,
    bbox: { pos: [x - 4, 18], relpos: [0, 0], size: [8, 4], angle: 0 },
    drawings: [], pads: [{ layers: [layer], pos: [x, 20], size: [2, 2], angle: 0, shape: 'circle', type: 'smd' }] });
  const data = { pcbdata: {
    metadata: { title: 'Fixture', revision: '', company: '', date: '' },
    edges_bbox: { minx: 0, miny: 0, maxx: 100, maxy: 50 },
    edges: [{ type: 'segment', start: [0, 0], end: [100, 0], width: 0.2 }],
    drawings: { silkscreen: { F: [], B: [] }, fabrication: { F: [], B: [] } },
    footprints: [footprint('R1', 'F', 20), footprint('R2', 'B', 60)]
  }, components: [
    { ref: 'R1', val: '10k', footprint: '0603', layer: 'F' },
    { ref: 'R2', val: '10k', footprint: '0603', layer: 'B' }
  ] };
  const html = template.replace('/*__BOARD_DATA__*/',
    `window.IBOM_CONFIG=${JSON.stringify({
      dark_mode: false, show_pads: true, show_fabrication: false,
      show_silkscreen: false, show_values: false, highlight_pin1: 'selected', redraw_on_drag: false,
      board_rotation: 9, offset_back_rotation: true, bom_view: 'left-right',
      layer_view: 'F', checkboxes: 'Sourced,Review,Placed', mark_when_checked: 'Review',
      moka_force_defaults: true, kicad_text_formatting: false,
      custom_metadata: '', fields: ['Value', 'Footprint']
    })};window.IBOM_DATA=${JSON.stringify(data)};`);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'moka-ibom-test-'));
  const file = path.join(dir, 'board.html');
  fs.writeFileSync(file, html);
  const browser = await chromium.launch({ headless: true, channel: 'chrome' });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(pathToFileURL(file).href);
    await page.waitForTimeout(500);
    if (errors.length) throw new Error(errors.join('; '));
    const initialText = await page.locator('#bombody').innerText();
    if (!initialText.includes('R1') || !initialText.includes('10k')) throw new Error(`Missing BOM data: ${initialText}`);
    const localizedUi = await page.locator('#bomcontrols').textContent();
    if (!localizedUi.includes('深色模式') || !localizedUi.includes('板旋转角度') ||
        !localizedUi.includes('配置和复选状态')) {
      throw new Error(`Chinese viewer labels are missing: ${localizedUi}`);
    }
    const localizedHeaders = await page.locator('#bomhead').innerText();
    if (!localizedHeaders.includes('位号') || !localizedHeaders.includes('器件值') ||
        !localizedHeaders.includes('封装')) {
      throw new Error(`Chinese BOM headers are missing: ${localizedHeaders}`);
    }
    // Seed conflicting viewer preferences, then reload. Allegro's embedded
    // configuration must win over stale localStorage values.
    await page.evaluate(() => {
      localStorage.setItem(storagePrefix + 'fabricationVisible', 'true');
      localStorage.setItem(storagePrefix + 'silkscreenVisible', 'true');
      localStorage.setItem(storagePrefix + 'valuesVisible', 'true');
      localStorage.setItem(storagePrefix + 'highlightpin1', 'all');
      localStorage.setItem(storagePrefix + 'redrawOnDrag', 'true');
      localStorage.setItem(storagePrefix + 'boardRotation', '90');
      localStorage.setItem(storagePrefix + 'offsetBackRotation', 'false');
      localStorage.setItem(storagePrefix + 'bomCheckboxes', 'Old');
      localStorage.setItem(storagePrefix + 'markWhenChecked', 'Old');
      localStorage.setItem(storagePrefix + 'canvaslayout', 'B');
      localStorage.setItem(storagePrefix + 'bomlayout', 'left-right');
    });
    await page.reload();
    await page.waitForTimeout(500);
    if (await page.locator('#fabricationCheckbox').isChecked()) throw new Error('Embedded fabrication setting was overridden by localStorage');
    if (await page.locator('#silkscreenCheckbox').isChecked()) throw new Error('Embedded silkscreen setting was overridden by localStorage');
    if (await page.locator('#valuesCheckbox').isChecked()) throw new Error('Embedded component value setting was ignored');
    const configuredLayout = await page.evaluate(() => ({ canvas: settings.canvaslayout, bom: settings.bomlayout }));
    if (configuredLayout.canvas !== 'F' || configuredLayout.bom !== 'left-right') throw new Error(`Embedded layout settings were ignored: ${JSON.stringify(configuredLayout)}`);
    const defaults = await page.evaluate(() => ({pin: settings.highlightpin1, redraw: settings.redrawOnDrag,
      rotation: settings.boardRotation, back: settings.offsetBackRotation,
      checkboxes: settings.checkboxes.join(','), mark: settings.markWhenChecked}));
    if (JSON.stringify(defaults) !== JSON.stringify({pin: 'selected', redraw: false, rotation: 45,
      back: true, checkboxes: 'Sourced,Review,Placed', mark: 'Review'})) {
      throw new Error(`Embedded display settings were ignored: ${JSON.stringify(defaults)}`);
    }
    const text = await page.locator('#bombody').innerText();
    if (!text.includes('R1') || !text.includes('10k')) throw new Error(`Missing front-side BOM data: ${text}`);
    const canvas = await page.locator('#F_bg').evaluate(c => ({ width: c.width, height: c.height }));
    if (!canvas.width || !canvas.height) throw new Error('Board canvas is blank');
    const visiblePixels = await page.locator('#F_bg').evaluate(c => {
      const pixels = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
      let count = 0;
      for (let i = 3; i < pixels.length; i += 4) if (pixels[i]) count++;
      return count;
    });
    if (!visiblePixels) throw new Error('Board canvas has no visible pixels');
    await page.locator('#filter').fill('missing');
    await page.waitForTimeout(200);
    if ((await page.locator('#bombody').innerText()).includes('R1')) throw new Error('Filtering failed');
    if (errors.length) throw new Error(errors.join('; '));
    console.log('Upstream InteractiveHtmlBom browser test passed.');
  } finally {
    await browser.close();
    fs.rmSync(dir, { recursive: true });
  }
}
main().catch(e => { console.error(e); process.exitCode = 1; });
