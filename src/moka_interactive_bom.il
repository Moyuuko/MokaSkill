; Standalone interactive BOM generator for Allegro.
; The board payload is kept in memory and embedded directly into HTML.

defvar(moka_ibom_install_dir axlOSSlash(axlGetVariable("MOKA_INSTALL_DIR") || "D:/Moka_Skill"))
defvar(moka_ibom_inline_export nil)
defvar(moka_ibom_payloads nil)
defvar(moka_ibom_config nil)
defvar(moka_ibom_config_form nil)
defvar(moka_ibom_include_tracks nil)
defvar(moka_ibom_include_nets nil)
defvar(moka_ibom_no_prompts nil)

; Keep the runtime path in sync when the loader is reloaded or the installer
; location is changed after this file was first evaluated.
defun( moka_ibom_sync_install_dir ()
    let((configured)
        configured = axlGetVariable("MOKA_INSTALL_DIR")
        when(configured
            moka_ibom_install_dir = axlOSSlash(configured)
        )
        moka_ibom_install_dir
    )
)

let((ibom_dir decoder exporter)
    ibom_dir = strcat(moka_ibom_install_dir "/interactive-bom")
    decoder = strcat(ibom_dir "/jsonDecode.il")
    exporter = strcat(ibom_dir "/exportJson.il")
    when(isFile(decoder) load(decoder))
    when(isFile(exporter) load(exporter))
)

axlCmdRegister("moka_ibom" 'moka_ibom_run ?cmdType "general")
axlCmdRegister("moka_ibom_config" 'moka_ibom_config_ui ?cmdType "general")

defun( moka_ibom_config_path ()
    moka_ibom_sync_install_dir()
    strcat(moka_ibom_install_dir "/moka_ibom.ini")
)

defun( moka_ibom_config_defaults ()
    let((cfg)
        cfg = makeTable("mokaIbomUserConfig" nil)
        cfg->dark_mode = nil
        cfg->show_pads = t
        cfg->show_fabrication = nil
        cfg->show_silkscreen = t
        cfg->show_values = nil
        cfg->revision = ""
        cfg->company = ""
        cfg->layer_view = "FB"
        cfg->bom_view = "left-right"
        cfg->highlight_pin1 = "none"
        cfg->redraw_on_drag = t
        cfg->board_rotation = 0
        cfg->offset_back_rotation = nil
        cfg->checkboxes = "Sourced,Placed"
        cfg->mark_when_checked = ""
        cfg->open_browser = t
        cfg->include_tracks = nil
        cfg->include_nets = nil
        cfg
    )
)

; Keep values written by Allegro's form API valid even when a popup returns
; its display label (or an empty value) instead of the popup token.
defun( moka_ibom_config_normalize (cfg)
    let((defaults)
        defaults = moka_ibom_config_defaults()
        cfg->dark_mode = if(cfg->dark_mode then t else nil)
        cfg->show_pads = if(cfg->show_pads then t else nil)
        cfg->show_fabrication = if(cfg->show_fabrication then t else nil)
        cfg->show_silkscreen = if(cfg->show_silkscreen then t else nil)
        cfg->show_values = if(cfg->show_values then t else nil)
        unless(stringp(cfg->revision) cfg->revision = defaults->revision)
        unless(stringp(cfg->company) cfg->company = defaults->company)
        cfg->redraw_on_drag = if(cfg->redraw_on_drag then t else nil)
        cfg->offset_back_rotation = if(cfg->offset_back_rotation then t else nil)
        cfg->open_browser = if(cfg->open_browser then t else nil)
        cfg->include_tracks = if(cfg->include_tracks then t else nil)
        cfg->include_nets = if(cfg->include_nets then t else nil)
        when(equal(cfg->layer_view "Front") cfg->layer_view = "F")
        when(equal(cfg->layer_view "Front + Back") cfg->layer_view = "FB")
        when(equal(cfg->layer_view "Back") cfg->layer_view = "B")
        when(equal(cfg->layer_view moka_ibom_ui_text("layer_front")) cfg->layer_view = "F")
        when(equal(cfg->layer_view moka_ibom_ui_text("layer_front_back")) cfg->layer_view = "FB")
        when(equal(cfg->layer_view moka_ibom_ui_text("layer_back")) cfg->layer_view = "B")
        when(equal(cfg->bom_view "Left / Right") cfg->bom_view = "left-right")
        when(equal(cfg->bom_view "Top / Bottom") cfg->bom_view = "top-bottom")
        when(equal(cfg->bom_view "BOM Only") cfg->bom_view = "bom-only")
        when(equal(cfg->bom_view moka_ibom_ui_text("bom_left_right")) cfg->bom_view = "left-right")
        when(equal(cfg->bom_view moka_ibom_ui_text("bom_top_bottom")) cfg->bom_view = "top-bottom")
        when(equal(cfg->bom_view moka_ibom_ui_text("bom_only")) cfg->bom_view = "bom-only")
        when(equal(cfg->highlight_pin1 "All") cfg->highlight_pin1 = "all")
        when(equal(cfg->highlight_pin1 "Selected") cfg->highlight_pin1 = "selected")
        when(equal(cfg->highlight_pin1 "None") cfg->highlight_pin1 = "none")
        when(equal(cfg->highlight_pin1 moka_ibom_ui_text("highlight_none")) cfg->highlight_pin1 = "none")
        when(equal(cfg->highlight_pin1 moka_ibom_ui_text("highlight_all")) cfg->highlight_pin1 = "all")
        when(equal(cfg->highlight_pin1 moka_ibom_ui_text("highlight_selected")) cfg->highlight_pin1 = "selected")
        unless(member(cfg->highlight_pin1 list("none" "all" "selected"))
            cfg->highlight_pin1 = "none"
        )
        unless(numberp(cfg->board_rotation)
            cfg->board_rotation = atoi(cfg->board_rotation || "0")
        )
        unless(numberp(cfg->board_rotation) cfg->board_rotation = 0)
        when(cfg->board_rotation < -180 cfg->board_rotation = -180)
        when(cfg->board_rotation > 180 cfg->board_rotation = 180)
        cfg->board_rotation = 5 * round(cfg->board_rotation / 5.0)
        unless(stringp(cfg->checkboxes) cfg->checkboxes = defaults->checkboxes)
        unless(stringp(cfg->mark_when_checked) cfg->mark_when_checked = defaults->mark_when_checked)
        unless(member(cfg->layer_view list("F" "FB" "B"))
            cfg->layer_view = defaults->layer_view
        )
        unless(member(cfg->bom_view list("bom-only" "left-right" "top-bottom"))
            cfg->bom_view = defaults->bom_view
        )
        cfg
    )
)

defun( moka_ibom_config_read ()
    let((cfg port line separator key value)
        cfg = moka_ibom_config_defaults()
        when(isFile(moka_ibom_config_path())
            port = infile(moka_ibom_config_path())
            when(port
                while(gets(line port)
                    line = buildString(parseString(line "\n\r") "")
                    separator = nindex(line "=")
                    when(separator && separator > 1
                        key = substring(line 1 separator - 1)
                        value = if(separator < strlen(line) then substring(line separator + 1) else "")
                        case(key
                            ("dark_mode" cfg->dark_mode = equal(value "1"))
                            ("show_pads" cfg->show_pads = equal(value "1"))
                            ("show_fabrication" cfg->show_fabrication = equal(value "1"))
                            ("show_silkscreen" cfg->show_silkscreen = equal(value "1"))
                            ("show_values" cfg->show_values = equal(value "1"))
                            ("revision" cfg->revision = value)
                            ("company" cfg->company = value)
                            ("layer_view" when(member(value list("F" "FB" "B")) cfg->layer_view = value))
                            ("bom_view" when(member(value list("bom-only" "left-right" "top-bottom")) cfg->bom_view = value))
                            ("highlight_pin1" cfg->highlight_pin1 = value)
                            ("redraw_on_drag" cfg->redraw_on_drag = equal(value "1"))
                            ("board_rotation" cfg->board_rotation = atoi(value))
                            ("offset_back_rotation" cfg->offset_back_rotation = equal(value "1"))
                            ("checkboxes" cfg->checkboxes = value)
                            ("mark_when_checked" cfg->mark_when_checked = value)
                            ("open_browser" cfg->open_browser = equal(value "1"))
                            ("include_tracks" cfg->include_tracks = equal(value "1"))
                            ("include_nets" cfg->include_nets = equal(value "1"))
                        )
                    )
                )
                close(port)
            )
        )
        moka_ibom_config = moka_ibom_config_normalize(cfg)
        moka_ibom_config
    )
)

defun( moka_ibom_config_write (cfg)
    let((port)
        cfg = moka_ibom_config_normalize(cfg)
        port = outfile(moka_ibom_config_path())
        when(port
            fprintf(port "dark_mode=%d\n" if(cfg->dark_mode then 1 else 0))
            fprintf(port "show_pads=%d\n" if(cfg->show_pads then 1 else 0))
            fprintf(port "show_fabrication=%d\n" if(cfg->show_fabrication then 1 else 0))
            fprintf(port "show_silkscreen=%d\n" if(cfg->show_silkscreen then 1 else 0))
            fprintf(port "show_values=%d\n" if(cfg->show_values then 1 else 0))
            fprintf(port "revision=%s\n" cfg->revision)
            fprintf(port "company=%s\n" cfg->company)
            fprintf(port "layer_view=%s\n" cfg->layer_view)
            fprintf(port "bom_view=%s\n" cfg->bom_view)
            fprintf(port "highlight_pin1=%s\n" cfg->highlight_pin1)
            fprintf(port "redraw_on_drag=%d\n" if(cfg->redraw_on_drag then 1 else 0))
            fprintf(port "board_rotation=%d\n" cfg->board_rotation)
            fprintf(port "offset_back_rotation=%d\n" if(cfg->offset_back_rotation then 1 else 0))
            fprintf(port "checkboxes=%s\n" cfg->checkboxes)
            fprintf(port "mark_when_checked=%s\n" cfg->mark_when_checked)
            fprintf(port "open_browser=%d\n" if(cfg->open_browser then 1 else 0))
            fprintf(port "include_tracks=%d\n" if(cfg->include_tracks then 1 else 0))
            fprintf(port "include_nets=%d\n" if(cfg->include_nets then 1 else 0))
            close(port)
            moka_ibom_config = cfg
            t
        )
    )
)

; Allegro form strings follow the same CP936 octal-escape convention used by
; the other MokaSkill panels (for example cct_ui_text in moka_copper_corner).
defun( moka_ibom_ui_text (key)
    case(key
        ("title" "Moka \275\273\273\245\312\275 BOM \305\344\326\303")
        ("html_source" "HTML \317\324\312\276\304\254\310\317\326\265")
        ("export_info" "\265\274\263\366\320\305\317\242")
        ("dark_mode" "\304\254\310\317\312\271\323\303\311\356\311\253\304\243\312\275")
        ("show_pads" "\304\254\310\317\317\324\312\276\272\270\305\314")
        ("show_fabrication" "\304\254\310\317\317\324\312\276\327\260\305\344\262\343")
        ("show_silkscreen" "\304\254\310\317\313\277\323\241")
        ("show_values" "\304\254\310\317\317\324\312\276\306\367\274\376\326\265")
        ("open_browser" "\265\274\263\366\272\363\327\324\266\257\264\362\277\252\344\257\300\300\306\367")
        ("redraw_on_drag" "\315\317\266\257\312\261\326\330\273\346\265\347\302\267\260\345")
        ("offset_back_rotation" "\261\263\303\346\320\375\327\252 180 \266\310")
        ("revision" "\260\346\261\276\272\305")
        ("company" "\271\253\313\276\303\373\263\306")
        ("html_options" "\317\324\312\276\262\343")
        ("layer_front" "\325\375\303\346")
        ("layer_front_back" "\325\375\303\346 + \261\263\303\346")
        ("layer_back" "\261\263\303\346")
        ("bom_view" "BOM \262\274\276\326")
        ("bom_left_right" "\327\363\323\322\262\274\276\326")
        ("bom_top_bottom" "\311\317\317\302\262\274\276\326")
        ("bom_only" "\275\366\317\324\312\276 BOM")
        ("highlight_none" "\262\273\270\337\301\301")
        ("highlight_all" "\310\253\262\277\306\367\274\376")
        ("highlight_selected" "\321\241\326\320\306\367\274\376")
        ("highlight_pin" "\322\273\275\305\270\337\301\301")
        ("board_rotation" "\260\345\320\375\327\252\275\307\266\310\243\250\266\310\243\251")
        ("checkboxes" "BOM \270\264\321\241\301\320\243\250\266\272\272\305\267\326\270\364\243\251")
        ("mark_when_checked" "\271\264\321\241\272\363\261\352\274\307\301\320")
        ("include_tracks" "\260\374\272\254\327\337\317\337\272\315\315\255\306\244\312\375\276\335")
        ("include_nets" "\260\374\272\254\315\370\261\355\312\375\276\335")
        ("apply" "\261\243\264\346\305\344\326\303")
        ("export" "\265\274\263\366")
        ("close" "\271\330\261\325")
        (t "")
    )
)

defun( moka_ibom_config_form_file (file_name)
    let((port)
        port = outfile(file_name)
        when(port
            fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\n")
            fprintf(port "FORM\nFIXED\nPORT 92 42\nHEADER \"%s\"\nTILE\n" moka_ibom_ui_text("title"))
            fprintf(port "TEXT \"%s\"\nTLOC 2 2\nENDTEXT\n" moka_ibom_ui_text("html_source"))
            fprintf(port "FIELD dark_mode\nFLOC 2 4\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("dark_mode"))
            fprintf(port "FIELD show_pads\nFLOC 2 7\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("show_pads"))
            fprintf(port "FIELD show_fabrication\nFLOC 2 10\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("show_fabrication"))
            fprintf(port "FIELD show_silkscreen\nFLOC 2 13\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("show_silkscreen"))
            fprintf(port "FIELD show_values\nFLOC 2 16\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("show_values"))
            fprintf(port "FIELD open_browser\nFLOC 2 19\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("open_browser"))
            fprintf(port "FIELD redraw_on_drag\nFLOC 2 22\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("redraw_on_drag"))
            fprintf(port "FIELD offset_back_rotation\nFLOC 2 25\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("offset_back_rotation"))
            fprintf(port "TEXT \"%s\"\nTLOC 42 2\nENDTEXT\n" moka_ibom_ui_text("export_info"))
            fprintf(port "TEXT \"%s\"\nTLOC 42 4\nENDTEXT\n" moka_ibom_ui_text("revision"))
            fprintf(port "FIELD revision\nFLOC 55 4\nSTRFILLIN 30 80\nENDFIELD\n")
            fprintf(port "TEXT \"%s\"\nTLOC 42 7\nENDTEXT\n" moka_ibom_ui_text("company"))
            fprintf(port "FIELD company\nFLOC 55 7\nSTRFILLIN 30 80\nENDFIELD\n")
            fprintf(port "TEXT \"%s\"\nTLOC 42 10\nENDTEXT\n" moka_ibom_ui_text("html_options"))
            fprintf(port "POPUP <LAYERVIEW> \"%s\" \"F\".\n" moka_ibom_ui_text("layer_front"))
            fprintf(port "POPUP <LAYERVIEW> \"%s\" \"FB\".\n" moka_ibom_ui_text("layer_front_back"))
            fprintf(port "POPUP <LAYERVIEW> \"%s\" \"B\".\n" moka_ibom_ui_text("layer_back"))
            fprintf(port "FIELD layer_view\nFLOC 55 12\nENUMSET 16\nPOP \"LAYERVIEW\"\nENDFIELD\n")
            fprintf(port "TEXT \"%s\"\nTLOC 42 16\nENDTEXT\n" moka_ibom_ui_text("bom_view"))
            fprintf(port "POPUP <BOMVIEW> \"%s\" \"left-right\".\n" moka_ibom_ui_text("bom_left_right"))
            fprintf(port "POPUP <BOMVIEW> \"%s\" \"top-bottom\".\n" moka_ibom_ui_text("bom_top_bottom"))
            fprintf(port "POPUP <BOMVIEW> \"%s\" \"bom-only\".\n" moka_ibom_ui_text("bom_only"))
            fprintf(port "FIELD bom_view\nFLOC 55 18\nENUMSET 16\nPOP \"BOMVIEW\"\nENDFIELD\n")
            fprintf(port "POPUP <HIGHLIGHTPIN> \"%s\" \"none\".\n" moka_ibom_ui_text("highlight_none"))
            fprintf(port "POPUP <HIGHLIGHTPIN> \"%s\" \"all\".\n" moka_ibom_ui_text("highlight_all"))
            fprintf(port "POPUP <HIGHLIGHTPIN> \"%s\" \"selected\".\n" moka_ibom_ui_text("highlight_selected"))
            fprintf(port "TEXT \"%s\"\nTLOC 42 22\nENDTEXT\n" moka_ibom_ui_text("highlight_pin"))
            fprintf(port "FIELD highlight_pin1\nFLOC 55 24\nENUMSET 16\nPOP \"HIGHLIGHTPIN\"\nENDFIELD\n")
            fprintf(port "TEXT \"%s\"\nTLOC 42 26\nENDTEXT\n" moka_ibom_ui_text("board_rotation"))
            fprintf(port "FIELD board_rotation\nFLOC 70 26\nINTFILLIN 6 3\nMIN -180\nMAX 180\nENDFIELD\n")
            fprintf(port "TEXT \"%s\"\nTLOC 42 29\nENDTEXT\n" moka_ibom_ui_text("checkboxes"))
            fprintf(port "FIELD checkboxes\nFLOC 42 31\nSTRFILLIN 42 80\nENDFIELD\n")
            fprintf(port "TEXT \"%s\"\nTLOC 42 34\nENDTEXT\n" moka_ibom_ui_text("mark_when_checked"))
            fprintf(port "FIELD mark_when_checked\nFLOC 42 36\nSTRFILLIN 42 80\nENDFIELD\n")
            fprintf(port "FIELD include_tracks\nFLOC 2 29\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("include_tracks"))
            fprintf(port "FIELD include_nets\nFLOC 2 32\nCHECKLIST \"%s\"\nENDFIELD\n" moka_ibom_ui_text("include_nets"))
            fprintf(port "FIELD btn_apply\nFLOC 42 38\nMENUBUTTON \"%s\" 13 3\nENDFIELD\n" moka_ibom_ui_text("apply"))
            fprintf(port "FIELD btn_export\nFLOC 57 38\nMENUBUTTON \"%s\" 13 3\nENDFIELD\n" moka_ibom_ui_text("export"))
            fprintf(port "FIELD btn_close\nFLOC 72 38\nMENUBUTTON \"%s\" 11 3\nENDFIELD\n" moka_ibom_ui_text("close"))
            fprintf(port "ENDTILE\nENDFORM\n")
            close(port)
            t
        )
    )
)

defun( moka_ibom_config_save_form (form)
    let((cfg layer_value bom_value)
        cfg = moka_ibom_config
        cfg->dark_mode = axlFormGetField(form "dark_mode")
        cfg->show_pads = axlFormGetField(form "show_pads")
        cfg->show_fabrication = axlFormGetField(form "show_fabrication")
        cfg->show_silkscreen = axlFormGetField(form "show_silkscreen")
        cfg->show_values = axlFormGetField(form "show_values")
        cfg->revision = axlFormGetField(form "revision")
        cfg->company = axlFormGetField(form "company")
        cfg->open_browser = axlFormGetField(form "open_browser")
        cfg->redraw_on_drag = axlFormGetField(form "redraw_on_drag")
        cfg->offset_back_rotation = axlFormGetField(form "offset_back_rotation")
        cfg->board_rotation = axlFormGetField(form "board_rotation")
        cfg->highlight_pin1 = axlFormGetField(form "highlight_pin1")
        cfg->checkboxes = axlFormGetField(form "checkboxes")
        cfg->mark_when_checked = axlFormGetField(form "mark_when_checked")
        layer_value = axlFormGetField(form "layer_view")
        bom_value = axlFormGetField(form "bom_view")
        when(layer_value cfg->layer_view = layer_value)
        when(bom_value cfg->bom_view = bom_value)
        cfg->include_tracks = axlFormGetField(form "include_tracks")
        cfg->include_nets = axlFormGetField(form "include_nets")
        if(moka_ibom_config_write(cfg) then
            moka_ibom_config = moka_ibom_config_read()
            axlMsgPut(sprintf(nil "Interactive BOM settings saved: %s" moka_ibom_config_path()))
            t
        else
            axlUIConfirm(sprintf(nil "Could not save Interactive BOM settings: %s" moka_ibom_config_path()) 'error)
            nil
        )
    )
)

defun( moka_ibom_config_form_cb (form)
    if(form->doneState > 0 then
        moka_ibom_config_form = nil
    else
        case(form->curField
            ("btn_apply"
                when(moka_ibom_config_save_form(form)
                    moka_ibom_config_form = nil
                    axlFormClose(form)
                )
            )
            ("btn_export"
                when(moka_ibom_config_save_form(form)
                    moka_ibom_config_form = nil
                    axlFormClose(form)
                    moka_ibom_run()
                )
            )
            ("btn_close"
                moka_ibom_config_form = nil
                axlFormClose(form)
            )
        )
    )
    t
)

defun( moka_ibom_config_ui ()
    let((file form cfg)
        cfg = moka_ibom_config_read()
        if(moka_ibom_config_form then
            axlFormDisplay(moka_ibom_config_form)
        else
            file = axlTempFile(t)
            when(moka_ibom_config_form_file(file)
                form = axlFormCreate(gensym() file nil 'moka_ibom_config_form_cb t)
                when(isFile(file) errset(axlTempFileRemove(file) nil))
                when(form
                    moka_ibom_config_form = form
                    axlFormBuildPopup(form "layer_view" list(list(moka_ibom_ui_text("layer_front") "F") list(moka_ibom_ui_text("layer_front_back") "FB") list(moka_ibom_ui_text("layer_back") "B")))
                    axlFormBuildPopup(form "bom_view" list(list(moka_ibom_ui_text("bom_left_right") "left-right") list(moka_ibom_ui_text("bom_top_bottom") "top-bottom") list(moka_ibom_ui_text("bom_only") "bom-only")))
                    axlFormBuildPopup(form "highlight_pin1" list(list(moka_ibom_ui_text("highlight_none") "none") list(moka_ibom_ui_text("highlight_all") "all") list(moka_ibom_ui_text("highlight_selected") "selected")))
                    axlFormSetField(form "dark_mode" cfg->dark_mode)
                    axlFormSetField(form "show_pads" cfg->show_pads)
                    axlFormSetField(form "show_fabrication" cfg->show_fabrication)
                    axlFormSetField(form "show_silkscreen" cfg->show_silkscreen)
                    axlFormSetField(form "show_values" cfg->show_values)
                    axlFormSetField(form "revision" cfg->revision)
                    axlFormSetField(form "company" cfg->company)
                    axlFormSetField(form "open_browser" cfg->open_browser)
                    axlFormSetField(form "redraw_on_drag" cfg->redraw_on_drag)
                    axlFormSetField(form "offset_back_rotation" cfg->offset_back_rotation)
                    axlFormSetField(form "board_rotation" cfg->board_rotation)
                    axlFormSetField(form "highlight_pin1" cfg->highlight_pin1)
                    axlFormSetField(form "checkboxes" cfg->checkboxes)
                    axlFormSetField(form "mark_when_checked" cfg->mark_when_checked)
                    axlFormSetField(form "layer_view" cfg->layer_view)
                    axlFormSetField(form "bom_view" cfg->bom_view)
                    axlFormSetField(form "include_tracks" cfg->include_tracks)
                    axlFormSetField(form "include_nets" cfg->include_nets)
                    axlFormDisplay(form)
                )
            )
        )
        moka_ibom_config_form
    )
)

defun( moka_ibom_bool_js (value)
    if(value then "true" else "false")
)

defun( moka_ibom_string_js (value)
    pcreReplace(pcreCompile("</") sprintf(nil "%L" value) "<\\\\/" 0)
)

defun( moka_ibom_config_js ()
    let((cfg)
        cfg = if(moka_ibom_config then moka_ibom_config else moka_ibom_config_read())
        strcat(
            "window.IBOM_CONFIG={dark_mode:" moka_ibom_bool_js(cfg->dark_mode)
            ",show_pads:" moka_ibom_bool_js(cfg->show_pads)
            ",show_fabrication:" moka_ibom_bool_js(cfg->show_fabrication)
            ",show_silkscreen:" moka_ibom_bool_js(cfg->show_silkscreen)
            ",show_values:" moka_ibom_bool_js(cfg->show_values)
            ",layer_view:\"" cfg->layer_view "\",bom_view:\"" cfg->bom_view
            "\",open_browser:" moka_ibom_bool_js(cfg->open_browser)
            ",include_tracks:" moka_ibom_bool_js(cfg->include_tracks)
            ",include_nets:" moka_ibom_bool_js(cfg->include_nets)
            ",highlight_pin1:\"" cfg->highlight_pin1 "\",redraw_on_drag:" moka_ibom_bool_js(cfg->redraw_on_drag)
            ",board_rotation:" sprintf(nil "%d" cfg->board_rotation / 5)
            ",offset_back_rotation:" moka_ibom_bool_js(cfg->offset_back_rotation)
            ",checkboxes:" moka_ibom_string_js(cfg->checkboxes)
            ",mark_when_checked:" moka_ibom_string_js(cfg->mark_when_checked)
            ",moka_force_defaults:true,kicad_text_formatting:false,custom_metadata:\"\",fields:[\"Value\",\"Footprint\"]};\n")
    )
)

defun( moka_ibom_default_layer_config ()
    let((root settings silk fab sideF sideB)
        root = makeTable("mokaIbomConfig" nil)
        settings = makeTable("mokaIbomSettings" nil)
        settings->exportInnerLayer = nil
        settings->renderViaHoles = nil
        settings->textAsSvgPaths = t
        settings->excludeDNP = nil
        settings->pcbLinewidth = "design"
        settings->fabricationLayerLinewidth = "design"
        settings->silkscreenLayerLinewidth = "design"
        settings->marginTop = 0
        settings->marginRight = 0
        settings->marginBottom = 0
        settings->marginLeft = 0
        root->settings = settings
        silk = makeTable("mokaIbomSilkscreen" nil)
        fab = makeTable("mokaIbomFabrication" nil)
        sideF = makeTable("mokaIbomFrontSilkscreen" nil)
        sideF->layers = list("BOARD GEOMETRY/SILKSCREEN_TOP" "PACKAGE GEOMETRY/SILKSCREEN_TOP" "REF DES/SILKSCREEN_TOP")
        sideF->refdes = "REF DES/SILKSCREEN_TOP"
        sideF->value = ""
        silk->F = sideF
        sideB = makeTable("mokaIbomBackSilkscreen" nil)
        sideB->layers = list("BOARD GEOMETRY/SILKSCREEN_BOTTOM" "PACKAGE GEOMETRY/SILKSCREEN_BOTTOM" "REF DES/SILKSCREEN_BOTTOM")
        sideB->refdes = "REF DES/SILKSCREEN_BOTTOM"
        sideB->value = ""
        silk->B = sideB
        sideF = makeTable("mokaIbomFrontFabrication" nil)
        sideF->layers = list("BOARD GEOMETRY/ASSEMBLY_TOP" "PACKAGE GEOMETRY/ASSEMBLY_TOP" "REF DES/ASSEMBLY_TOP" "COMPONENT VALUE/ASSEMBLY_TOP")
        sideF->refdes = "REF DES/ASSEMBLY_TOP"
        sideF->value = "COMPONENT VALUE/ASSEMBLY_TOP"
        fab->F = sideF
        sideB = makeTable("mokaIbomBackFabrication" nil)
        sideB->layers = list("BOARD GEOMETRY/ASSEMBLY_BOTTOM" "PACKAGE GEOMETRY/ASSEMBLY_BOTTOM" "REF DES/ASSEMBLY_BOTTOM" "COMPONENT VALUE/ASSEMBLY_BOTTOM")
        sideB->refdes = "REF DES/ASSEMBLY_BOTTOM"
        sideB->value = "COMPONENT VALUE/ASSEMBLY_BOTTOM"
        fab->B = sideB
        root->silkscreen = silk
        root->fabrication = fab
        root
    )
)

defun( moka_ibom_template ()
    moka_ibom_sync_install_dir()
    strcat(moka_ibom_install_dir "/interactive-bom/upstream_template.html")
)

defun( moka_ibom_normalize_path (path)
    axlOSSlash(path)
)

defun( moka_ibom_payload_basename (source)
    let((parts file stem)
        parts = parseString(moka_ibom_normalize_path(source) "/")
        file = if(parts then car(last(parts)) else source)
        stem = car(parseString(file "."))
        strcat(stem "_ibom.html")
    )
)

defun( moka_ibom_write_html (payload source output_dir)
    let((template input output line target ok safe_payload)
        template = moka_ibom_template()
        target = strcat(output_dir "/" moka_ibom_payload_basename(source))
        ok = nil
        when(isFile(template)
            unless(isDir(output_dir) createDir(output_dir))
            input = infile(template)
            output = outfile(target)
            if(input && output then
                while(gets(line input)
                    if(index(line "/*__BOARD_DATA__*/") then
                        fprintf(output "%s" moka_ibom_config_js())
                        fprintf(output "window.IBOM_DATA=")
                        safe_payload = pcreReplace(pcreCompile("</") payload "<\\/" 0)
                        foreach(payload_line parseString(safe_payload "\n")
                            fprintf(output "%s\n" payload_line)
                        )
                        fprintf(output ";\n")
                    else
                        fprintf(output "%s\n" line)
                    )
                )
                close(input)
                close(output)
                ok = isFile(target)
            else
                when(input close(input))
                when(output close(output))
            )
        )
        if(ok then target else nil)
    )
)

defun( moka_ibom_run ()
    let((export_result payload_records record html_files html_file output_dir failed)
        moka_ibom_sync_install_dir()
        if(!axlCurrentDesign() then
            axlUIConfirm("Open a saved Allegro board before exporting Interactive BOM." 'error)
            nil
        else
            moka_ibom_config_read()
            moka_ibom_include_tracks = moka_ibom_config->include_tracks
            moka_ibom_include_nets = moka_ibom_config->include_nets
            moka_ibom_no_prompts = t
            moka_ibom_payloads = nil
            moka_ibom_inline_export = t
            unwindProtect(
                progn(
                    export_result = errset(exportJson(?rev moka_ibom_config->revision ?company moka_ibom_config->company) nil)
                )
                progn(
                    moka_ibom_inline_export = nil
                    moka_ibom_no_prompts = nil
                )
            )
            payload_records = reverse(moka_ibom_payloads)
            if(!export_result || !payload_records then
                axlUIConfirm("Allegro did not provide board data for HTML export. Check the command window." 'error)
                nil
            else
                output_dir = strcat(moka_ibom_normalize_path(getWorkingDir()) "/ibom")
                html_files = nil
                failed = nil
                foreach(record payload_records
                    html_file = moka_ibom_write_html(cadr(record) car(record) output_dir)
                    if(html_file then
                        html_files = cons(html_file html_files)
                    else
                        failed = t
                        axlMsgPut(sprintf(nil "Could not write Interactive BOM: %s" car(record)))
                    )
                )
                if(failed || !html_files then
                    axlUIConfirm("Interactive BOM export failed while writing HTML." 'error)
                    nil
                else
                    html_files = reverse(html_files)
                    foreach(html_file html_files
                        axlMsgPut(sprintf(nil "Interactive BOM created: %s" html_file))
                    )
                    when(moka_ibom_config->open_browser
                        system(strcat("start \"\" \"" axlOSBackSlash(car(html_files)) "\""))
                    )
                    axlUIConfirm(sprintf(nil "Interactive BOM export complete.\n%s" buildString(html_files "\n")) 'info)
                    t
                )
            )
        )
    )
)
