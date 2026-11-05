/* Adapt the Allegro collector's in-memory data to InteractiveHtmlBom's web contract. */
var config = window.IBOM_CONFIG || {
  dark_mode: false, show_pads: true, show_fabrication: true,
  show_silkscreen: true, show_values: false, highlight_pin1: "none", redraw_on_drag: true,
  board_rotation: 0, offset_back_rotation: false, checkboxes: "Sourced,Placed",
  mark_when_checked: "", bom_view: "left-right", layer_view: "FB",
  moka_force_defaults: true,
  kicad_text_formatting: false, custom_metadata: "", fields: ["Value", "Footprint"]
};
var pcbdata = window.IBOM_DATA.pcbdata;
var mokaComponents = window.IBOM_DATA.components;
var mokaGroups = new Map();
pcbdata.bom = { both: [], F: [], B: [], skipped: [], fields: {} };
mokaComponents.forEach(function(component, index) {
  var fields = [component.val || "", component.footprint || ""];
  pcbdata.bom.fields[index] = fields;
  if (component.extra_fields && component.extra_fields.DNP) {
    pcbdata.bom.skipped.push(index);
    return;
  }
  var groupKey = JSON.stringify(fields);
  if (!mokaGroups.has(groupKey)) mokaGroups.set(groupKey, []);
  mokaGroups.get(groupKey).push([component.ref, index]);
});
mokaGroups.forEach(function(group) {
  pcbdata.bom.both.push(group);
  ["F", "B"].forEach(function(side) {
    var subset = group.filter(function(item) {
      return pcbdata.footprints[item[1]].layer === side;
    });
    if (subset.length) pcbdata.bom[side].push(subset);
  });
});
pcbdata.ibom_version = "v2.12.0";
