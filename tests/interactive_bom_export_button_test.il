; Exercise the form callback with Allegro APIs replaced by lightweight stubs.
defvar(_ibom_test_dir strcat(getWorkingDir() "/tests"))
defun(axlGetVariable (name) _ibom_test_dir)
defun(axlOSSlash (path) path)
defun(axlCmdRegister (@rest args) t)
unless(errset(load("src/moka_interactive_bom.il") t) exit(1))
defun(axlFormGetField (form field) form[field])
defun(axlFormClose (form) _ibom_closed = t)
defun(axlMsgPut (@rest args) t)
defun(axlUIConfirm (@rest args) t)
defun(axlCurrentDesign () t)
defun(exportJson (@key rev company)
    _ibom_export_called = t
    _ibom_export_revision = rev
    _ibom_export_company = company
    unless(moka_ibom_inline_export && moka_ibom_no_prompts
        error("Export flags were not set"))
    moka_ibom_payloads = list(list("fixture.brd" "{}"))
    t
)
defun(moka_ibom_write_html (payload source output_dir) "fixture_ibom.html")

unless(errset(let((form config_path)
    config_path = moka_ibom_config_path()
    when(isFile(config_path) error("Refusing to overwrite existing test settings"))
    moka_ibom_config = moka_ibom_config_defaults()
    form = makeTable("ibomTestForm" nil)
    form->doneState = 0
    form->curField = "btn_export"
    form["revision"] = "REV-B"
    form["company"] = "Fixture"
    form["show_pads"] = t
    form["show_silkscreen"] = t
    form["redraw_on_drag"] = t
    form["open_browser"] = nil
    form["layer_view"] = "F"
    form["bom_view"] = "left-right"
    form["highlight_pin1"] = "none"
    form["board_rotation"] = 0
    form["checkboxes"] = ""
    form["mark_when_checked"] = ""
    _ibom_closed = nil
    _ibom_export_called = nil
    moka_ibom_config_form_cb(form)
    unless(_ibom_closed && _ibom_export_called error("Export button did not close and export"))
    unless(equal(_ibom_export_revision "REV-B") && equal(_ibom_export_company "Fixture")
        error("Export did not use the current form fields"))
    unless(moka_ibom_config->show_silkscreen && moka_ibom_config->show_pads
        error("Export did not preserve current form settings"))
    when(moka_ibom_inline_export || moka_ibom_no_prompts
        error("Export flags were not cleaned up"))
    deleteFile(config_path)
) t) exit(1))
printf("Interactive BOM export button test passed.\n")
exit()
