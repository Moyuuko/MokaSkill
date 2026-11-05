; Load the native exporter without an Allegro database and verify its layer map.
defvar(_moka_smoke_install_dir strcat(getWorkingDir() "/src"))
defun( axlGetVariable (name) _moka_smoke_install_dir)
defun( axlOSSlash (path) path)
defun( axlCmdRegister (@rest args) t)
unless(errset(load("src/moka_interactive_bom.il") t) exit(1))
unless(errset(let((config user_config generated port line found_payload found_template found_config config_js form_path form_port form_line has_layer has_apply has_export has_revision has_company config_path)
    config = moka_ibom_default_layer_config()
    unless(member("PACKAGE GEOMETRY/SILKSCREEN_TOP" config->silkscreen->F->layers)
        error("Missing front silkscreen layer mapping")
    )
    when(member("COMPONENT VALUE/SILKSCREEN_TOP" config->silkscreen->F->layers)
        error("Component value silkscreen layer must not be exported")
    )
    when(member("COMPONENT VALUE/SILKSCREEN_BOTTOM" config->silkscreen->B->layers)
        error("Bottom component value silkscreen layer must not be exported")
    )
    unless(equal(config->silkscreen->F->value "")
        error("Component value silkscreen text mapping must be disabled")
    )
    unless(equal(config->fabrication->B->refdes "REF DES/ASSEMBLY_BOTTOM")
        error("Missing back assembly reference layer")
    )
    unless(equal(moka_ibom_payload_basename("C:/boards/test.json") "test_ibom.html")
        error("Invalid HTML output filename")
    )
    moka_ibom_config = nil
    config_js = moka_ibom_config_js()
    unless(index(config_js "show_fabrication:false")
        error("Interactive BOM display defaults are not serialized")
    )
    unless(index(config_js "show_pads:true") && index(config_js "show_silkscreen:true") &&
        index(config_js "open_browser:true") && index(config_js "redraw_on_drag:true")
        error("Interactive BOM requested defaults are not enabled")
    )
    unless(index(config_js "show_values:false")
        error("Component value display default is not serialized")
    )
    user_config = moka_ibom_config_defaults()
    user_config->dark_mode = t
    user_config->show_pads = nil
    user_config->show_fabrication = t
    user_config->show_silkscreen = t
    user_config->show_values = t
    user_config->revision = "REV-A"
    user_config->company = "Moka Electronics"
    user_config->include_tracks = t
    user_config->include_nets = t
    user_config->layer_view = "B"
    user_config->bom_view = "top-bottom"
    user_config->highlight_pin1 = "selected"
    user_config->redraw_on_drag = nil
    user_config->board_rotation = 47
    user_config->offset_back_rotation = t
    user_config->checkboxes = "Sourced,Review,Placed"
    user_config->mark_when_checked = "Review"
    _moka_smoke_install_dir = strcat(getWorkingDir() "/tests")
    moka_ibom_install_dir = _moka_smoke_install_dir
    config_path = moka_ibom_config_path()
    when(isFile(config_path) error("Smoke test settings file already exists; refusing to overwrite it"))
    unless(moka_ibom_config_write(user_config)
        error("Could not save Interactive BOM settings")
    )
    unless(isFile(config_path)
        error("Interactive BOM settings file was not created")
    )
    user_config = moka_ibom_config_read()
    unless(user_config->dark_mode error("Interactive BOM dark mode did not survive a save and reload"))
    when(user_config->show_pads error("Interactive BOM pad setting did not survive a save and reload"))
    unless(user_config->show_fabrication error("Interactive BOM fabrication setting did not survive a save and reload"))
    unless(user_config->show_values error("Canvas value setting did not survive a save and reload"))
    unless(equal(user_config->revision "REV-A") error("Revision did not survive save and reload"))
    unless(equal(user_config->company "Moka Electronics") error("Company did not survive save and reload"))
    unless(user_config->include_tracks && user_config->include_nets error("Collector options did not survive a save and reload"))
    unless(equal(user_config->layer_view "B") error("Interactive BOM layer setting did not survive a save and reload"))
    unless(equal(user_config->bom_view "top-bottom") error("Interactive BOM layout setting did not survive a save and reload"))
    unless(equal(user_config->highlight_pin1 "selected") error("Pin 1 setting did not survive save and reload"))
    when(user_config->redraw_on_drag error("Dragging setting did not survive save and reload"))
    unless(user_config->board_rotation == 45 error("Board rotation must round to the nearest five degrees"))
    unless(user_config->offset_back_rotation error("Back side rotation did not survive save and reload"))
    unless(equal(user_config->checkboxes "Sourced,Review,Placed") error("Checkbox columns did not survive save and reload"))
    unless(equal(user_config->mark_when_checked "Review") error("Mark column did not survive save and reload"))
    config_js = moka_ibom_config_js()
    unless(index(config_js "board_rotation:9") error("Upstream rotation unit must be degrees divided by five"))
    unless(index(config_js "highlight_pin1:\"selected\"") error("Pin highlight setting was not serialized"))
    unless(index(config_js "show_values:true") error("Canvas value setting was not serialized"))
    user_config->checkboxes = "Review \"quoted\",A\\B"
    config_js = moka_ibom_config_js()
    unless(index(config_js "\\\"quoted\\\"") error("Checkbox column quotes must be escaped in JavaScript"))
    unless(index(config_js "A\\\\B") error("Checkbox column backslashes must be escaped in JavaScript"))
    user_config->checkboxes = "</script>"
    config_js = moka_ibom_config_js()
    when(index(config_js "</script>") error("Checkbox column must not terminate the embedded script"))
    user_config->checkboxes = ""
    user_config->mark_when_checked = ""
    moka_ibom_config_write(user_config)
    user_config = moka_ibom_config_read()
    unless(equal(user_config->checkboxes "") error("Empty checkbox configuration was lost"))
    deleteFile(config_path)
    _moka_smoke_install_dir = strcat(getWorkingDir() "/src")
    moka_ibom_install_dir = _moka_smoke_install_dir
    moka_ibom_config = nil
    form_path = strcat(getWorkingDir() "/tests/moka_ibom_settings_smoke.form")
    when(isFile(form_path) deleteFile(form_path))
    unless(moka_ibom_config_form_file(form_path)
        error("Could not create Interactive BOM settings form")
    )
    form_port = infile(form_path)
    while(gets(form_line form_port)
        when(index(form_line "FIELD layer_view") has_layer = t)
        when(index(form_line "FIELD btn_apply") has_apply = t)
        when(index(form_line "FIELD btn_export") has_export = t)
        when(index(form_line "FIELD revision") has_revision = t)
        when(index(form_line "FIELD company") has_company = t)
    )
    close(form_port)
    deleteFile(form_path)
    unless(has_layer && has_apply && has_export && has_revision && has_company error("Interactive BOM settings form is incomplete"))
    generated = strcat(getWorkingDir() "/tests/moka_ibom_smoke_generated_ibom.html")
    when(isFile(generated)
        error("Smoke test output already exists; refusing to overwrite it")
    )
    unless(moka_ibom_write_html("{\"pcbdata\":{},\"components\":[]}" "moka_ibom_smoke_generated.json" strcat(getWorkingDir() "/tests"))
        error("Could not generate standalone HTML")
    )
    port = infile(generated)
    found_payload = nil
    found_template = nil
    while(gets(line port)
        when(index(line "window.IBOM_DATA=") found_payload = t)
        when(index(line "show_fabrication:false") found_config = t)
        when(index(line "<html lang=\"zh-CN\">") found_template = t)
    )
    close(port)
    deleteFile(generated)
    unless(found_payload && found_config && found_template error("Generated HTML is incomplete"))
) t) exit(1))
printf("Interactive BOM SKILL smoke test passed.\n")
exit()
