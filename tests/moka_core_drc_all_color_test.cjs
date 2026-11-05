const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(
  path.join(__dirname, "..", "src", "moka_core.il"),
  "utf8",
);

assert.match(
  source,
  /defun\( moka_update_drc_all_color \(form\)[\s\S]*?moka_get_color_safe\("DRC ERROR CLASS" "ALL"\)[\s\S]*?else\s+0[\s\S]*?axlFormSetField\(form "drc_all" color_idx\)/,
  "DRC ALL must use its subclass color when enabled and clear its indicator when disabled",
);
assert.match(
  source,
  /defun\( moka_toggle_drc_all \(form\)[\s\S]*?moka_drc_all = if\(moka_drc_all then nil else t\)[\s\S]*?moka_update_drc_all_color\(form\)/,
  "clicking DRC ALL must toggle state and refresh the color indicator",
);
assert.match(
  source,
  /moka_update_drc_all_color\(form\)\s+axlFormDisplay\(form\)/,
  "the saved DRC ALL state must be colored before the layer form is displayed",
);
assert.match(
  source,
  /\("drc_all"\s+moka_toggle_drc_all\(form\)\s+\)/,
  "the DRC ALL callback must use the color-aware toggle",
);
assert.doesNotMatch(
  source,
  /axlFormSetField\(form "drc_all" moka_drc_all\)/,
  "DRC ALL must not pass a boolean in place of the field color index",
);

console.log("Moka DRC ALL color-indicator regression checks passed.");
