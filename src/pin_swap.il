/*
  Moka Skill Pin Swap Module v1.0

  Commands:
    moka_pin_swap          - open the Moka Pin Swap control panel
    pin_swap               - open the Pin Swap control panel
    pin_swap_run           - internal interactive pin selection command
    pin_swap_pinmap_export - internal component Pinmap export command
    pin_swap_pinmap_import - internal Pinmap batch apply command

  The tool supports interactive two-pin swaps and validated batch swaps from an
  exported component Pinmap. It bypasses library PINSWAP groups and pin FIXED
  state. Connected clines are preserved when pin nets are reassigned.
*/

_fsp_finished = nil
_fsp_commit = nil
_fsp_mark = nil
_fsp_symbol = nil
_fsp_first_pin = nil
_fsp_swap_count = 0
_fsp_session_records = nil
_fsp_export_records = nil
_fsp_ui_form = nil
_fsp_ui_close_pending = nil
_fsp_ui_status = "\277\325\317\320"
_fsp_run_active = nil
_fsp_ui_list_items = nil
_fsp_pinmap_active = nil
_fsp_pinmap_finished = nil
_fsp_pinmap_cancelled = nil
_fsp_pinmap_highlights = nil
_fsp_export_net_colors = nil
_fsp_version = "1.0"
_fsp_panel_active = nil
_fsp_panel_action = nil
_fsp_ui_ministatus = nil

axlCmdRegister(
    "pin_swap_run"
    'pin_swap_cmd
    ?cmdType "interactive"
    ?doneCmd 'fsp_cb_done
    ?cancelCmd 'fsp_cb_cancel
)

axlCmdRegister(
    "pin_swap" 'fsp_ui_open
    ?cmdType "interactive"
    ?doneCmd 'fsp_panel_done
    ?cancelCmd 'fsp_panel_cancel)
axlCmdRegister(
    "moka_pin_swap" 'fsp_ui_open
    ?cmdType "interactive"
    ?doneCmd 'fsp_panel_done
    ?cancelCmd 'fsp_panel_cancel)
axlCmdRegister(
    "pin_swap_pinmap_export"
    'fsp_pinmap_export_cmd
    ?cmdType "interactive"
    ?doneCmd 'fsp_pinmap_cb_done
    ?cancelCmd 'fsp_pinmap_cb_cancel
)
axlCmdRegister("pin_swap_pinmap_import" 'fsp_pinmap_import_cmd ?cmdType "general")

defun( fsp_cb_done ()
    _fsp_finished = t
    _fsp_commit = t
    fsp_ui_set_status("\325\375\324\332\314\341\275\273\265\261\307\260\273\273 Pin \262\331\327\367...")
    axlCancelEnterFun()
)

defun( fsp_cb_cancel ()
    _fsp_finished = t
    _fsp_commit = nil
    fsp_ui_set_status("\325\375\324\332\310\241\317\373\262\242\273\330\271\366\265\261\307\260\273\273 Pin \262\331\327\367...")
    axlCancelEnterFun()
)

defun( fsp_pinmap_cb_done ()
    _fsp_pinmap_finished = t
    _fsp_pinmap_cancelled = nil
    axlCancelEnterFun()
)

defun( fsp_pinmap_cb_cancel ()
    _fsp_pinmap_finished = t
    _fsp_pinmap_cancelled = t
    fsp_ui_set_status("Pinmap \262\331\327\367\322\321\310\241\317\373\241\243")
    axlCancelEnterFun()
)

defun( fsp_clear_first_pin ()
    when(_fsp_first_pin
        errset(axlDehighlightObject(_fsp_first_pin t) nil)
        _fsp_first_pin = nil
    )
    fsp_ui_refresh()
)

defun( fsp_cb_oops ()
    if(_fsp_first_pin then
        fsp_clear_first_pin()
        axlMsgPut("Moka skill - Pin Swap: \265\332\322\273\322\375\275\305\322\321\307\345\263\375\241\243")
        fsp_ui_set_status("\265\332\322\273\322\375\275\305\322\321\307\345\263\375\243\254\307\353\326\330\320\302\321\241\324\361\265\332\322\273\322\375\275\305\241\243")
    else
        if(_fsp_mark && _fsp_swap_count > 0 then
            if(axlDBTransactionOops(_fsp_mark) then
                _fsp_swap_count = _fsp_swap_count - 1
                when(_fsp_session_records
                    _fsp_session_records = cdr(_fsp_session_records)
                )
                axlMsgPut("Moka skill - Pin Swap: \311\317\322\273\327\351\322\375\275\305\275\273\273\273\322\321\273\326\270\264\241\243")
                fsp_ui_set_status("\311\317\322\273\327\351\322\375\275\305\275\273\273\273\322\321\273\326\270\264\241\243")
            else
                axlMsgPut("Moka skill - Pin Swap: \316\336\267\250\273\326\270\264\311\317\322\273\327\351\322\375\275\305\275\273\273\273\241\243")
                fsp_ui_set_status("\316\336\267\250\273\326\270\264\311\317\322\273\327\351\322\375\275\305\275\273\273\273\241\243")
            )
        else
            axlMsgPut("Moka skill - Pin Swap: \303\273\323\320\277\311\263\267\317\372\265\304\262\331\327\367\241\243")
            fsp_ui_set_status("\303\273\323\320\277\311\263\267\317\372\265\304\262\331\327\367\241\243")
        )
    )
    axlClearSelSet()
    fsp_ui_refresh()
    axlCancelEnterFun()
)

defun( fsp_normalize_symbol (object)
    let((symbol)
        symbol = nil
        when(object
            case(object->objType
                ("symbol" symbol = object)
                ("component"
                    when(object->symbol
                        symbol = object->symbol
                    )
                )
            )
        )
        symbol
    )
)

defun( fsp_symbol_refdes (symbol)
    let((refdes)
        refdes = "<component>"
        when(symbol
            if(stringp(symbol->refdes) && strlen(symbol->refdes) > 0 then
                refdes = symbol->refdes
            else
                when(symbol->component && stringp(symbol->component->refdes)
                    refdes = symbol->component->refdes
                )
            )
        )
        refdes
    )
)

defun( fsp_pin_number (pin)
    let((number)
        number = "?"
        when(pin && pin->number
            if(stringp(pin->number) then
                number = pin->number
            else
                number = sprintf(nil "%L" pin->number)
            )
        )
        number
    )
)

defun( fsp_pin_label (pin)
    sprintf(nil "%s.%s" fsp_symbol_refdes(_fsp_symbol) fsp_pin_number(pin))
)

defun( fsp_pin_net (pin)
    let((net)
        net = nil
        when(pin && pin->net && stringp(pin->net->name) && strlen(pin->net->name) > 0
            net = pin->net
        )
        net
    )
)

defun( fsp_net_label (net)
    if(net && stringp(net->name) && strlen(net->name) > 0 then
        net->name
    else
        "<UNCONNECTED>"
    )
)

defun( fsp_net_custom_color_index (net)
    let((result color_index)
        color_index = nil
        when(net
            result = errset(axlIsCustomColored(net) nil)
            when(result && numberp(car(result))
                color_index = car(result)
            )
        )
        color_index
    )
)

defun( fsp_export_field (value)
    let((text)
        if(stringp(value) then
            text = value
        else
            text = sprintf(nil "%L" value)
        )
        buildString(parseString(text "\t\r\n") " ")
    )
)

defun( fsp_swap_record (pin1 net1 pin2 net2)
    let((pin1_label pin2_label)
        pin1_label = fsp_export_field(fsp_pin_label(pin1))
        pin2_label = fsp_export_field(fsp_pin_label(pin2))
        list(
            list(
                sprintf(nil "%s %s" pin1_label fsp_export_field(fsp_net_label(net1)))
                sprintf(nil "%s %s" pin1_label fsp_export_field(fsp_net_label(net2)))
            )
            list(
                sprintf(nil "%s %s" pin2_label fsp_export_field(fsp_net_label(net2)))
                sprintf(nil "%s %s" pin2_label fsp_export_field(fsp_net_label(net1)))
            )
        )
    )
)

defun( fsp_record_change_count (record)
    length(record)
)

defun( fsp_records_change_count (records)
    let((count record)
        count = 0
        foreach(record records
            count = count + fsp_record_change_count(record)
        )
        count
    )
)

defun( fsp_export_default_name ()
    let((design stamp)
        design = fsp_export_field(axlCurrentDesign())
        stamp = buildString(parseString(getCurrentTime() " :/") "")
        sprintf(nil "%s_force_pin_swap_%s.txt" design stamp)
    )
)

defun( fsp_write_export_file (file_name records)
    let((port record mapping ok)
        ok = nil
        port = outfile(file_name)
        if(port then
            fprintf(port "\273\273 Pin \307\260 -> \273\273 Pin \272\363\n")
            foreach(record records
                foreach(mapping record
                    fprintf(port "%s -> %s\n" nth(0 mapping) nth(1 mapping))
                )
            )
            close(port)
            ok = t
        )
        ok
    )
)

defun( fsp_export_pending ()
    let((file_name records change_count)
        if(!_fsp_export_records then
            axlMsgPut("Moka skill - Pin Swap: \303\273\323\320\264\375\265\274\263\366\265\304\322\321\314\341\275\273\273\273 Pin \320\305\317\242\241\243")
            fsp_ui_set_status("\303\273\323\320\277\311\265\274\263\366\265\304\322\321\314\341\275\273\273\273 Pin \320\305\317\242\241\243")
            nil
        else
            file_name = axlDMFileBrowse(
                nil
                t
                ?defaultName fsp_export_default_name()
                ?title "\265\274\263\366\273\273 Pin \320\305\317\242"
                ?optFilters "\273\273 Pin \316\304\261\276\316\304\274\376 (*.txt)|*.txt|"
            )
            if(!file_name then
                axlMsgPut("Moka skill - Pin Swap: \265\274\263\366\322\321\310\241\317\373\243\254\274\307\302\274\322\321\261\243\301\364\241\243")
                fsp_ui_set_status("\265\274\263\366\322\321\310\241\317\373\243\254\274\307\302\274\322\321\261\243\301\364\241\243")
                nil
            else
                records = reverse(_fsp_export_records)
                change_count = fsp_records_change_count(records)
                if(fsp_write_export_file(file_name records) then
                    _fsp_export_records = nil
                    axlMsgPut(sprintf(nil "Moka skill - Pin Swap: \322\321\265\274\263\366 %d \270\366\322\375\275\305\261\344\270\374\265\275 %s\241\243" change_count file_name))
                    fsp_ui_set_status(sprintf(nil "\322\321\265\274\263\366 %d \270\366\322\375\275\305\261\344\270\374\241\243" change_count))
                    t
                else
                    axlMsgPut("Moka skill - Pin Swap: \316\336\267\250\320\264\310\353\265\274\263\366\316\304\274\376\243\254\274\307\302\274\322\321\261\243\301\364\241\243")
                    fsp_ui_set_status("\265\274\263\366\312\247\260\334\243\254\274\307\302\274\322\321\261\243\301\364\241\243")
                    nil
                )
            )
        )
    )
)

defun( fsp_symbol_lessp (symbol1 symbol2)
    alphalessp(fsp_symbol_refdes(symbol1) fsp_symbol_refdes(symbol2))
)

defun( fsp_pin_lessp (pin1 pin2)
    alphalessp(fsp_pin_number(pin1) fsp_pin_number(pin2))
)

defun( fsp_number_lessp (number1 number2)
    number1 < number2
)

defun( fsp_number_greaterp (number1 number2)
    number1 > number2
)

defun( fsp_pinmap_quantize_coord (value)
    atof(sprintf(nil "%.6f" value))
)

defun( fsp_pinmap_coord_text (value)
    sprintf(nil "%.6f" value)
)

defun( fsp_pinmap_local_xy (pin)
    if(pin && pin->relxy then
        list(
            fsp_pinmap_quantize_coord(car(pin->relxy))
            fsp_pinmap_quantize_coord(cadr(pin->relxy))
        )
    else
        nil
    )
)

defun( fsp_pinmap_layout_entry_at (entries x_value y_value)
    let((result entry)
        result = nil
        foreach(entry entries
            when(!result && nth(2 entry) == x_value && nth(3 entry) == y_value
                result = entry
            )
        )
        result
    )
)

defun( fsp_pinmap_complete_grid_p (entries x_values y_values)
    let((complete x_value y_value)
        complete = length(entries) == length(x_values) * length(y_values)
        when(complete
            foreach(y_value y_values
                foreach(x_value x_values
                    unless(fsp_pinmap_layout_entry_at(entries x_value y_value)
                        complete = nil
                    )
                )
            )
        )
        complete
    )
)

defun( fsp_pinmap_layout_for_symbol (symbol)
    let((entries errors keys x_values y_values pin xy x_value y_value key net net_label color_index entry)
        entries = nil
        errors = nil
        keys = nil
        x_values = nil
        y_values = nil

        foreach(pin symbol->pins
            when(pin->objType == "pin" && !pin->isMech && pin->number
                xy = fsp_pinmap_local_xy(pin)
                if(!xy then
                    errors = cons(
                        sprintf(nil "%s.%s \303\273\323\320\306\367\274\376\261\276\265\330\322\375\275\305\327\370\261\352\241\243"
                            fsp_symbol_refdes(symbol) fsp_pin_number(pin))
                        errors
                    )
                else
                    x_value = car(xy)
                    y_value = cadr(xy)
                    key = sprintf(nil "%s,%s"
                        fsp_pinmap_coord_text(x_value)
                        fsp_pinmap_coord_text(y_value))
                    if(member(key keys) then
                        errors = cons(
                            sprintf(nil "%s \324\332\261\276\265\330\327\370\261\352 %s \311\317\264\346\324\332\266\340\270\366\302\337\274\255\322\375\275\305\241\243"
                                fsp_symbol_refdes(symbol) key)
                            errors
                        )
                    else
                        keys = cons(key keys)
                        unless(member(x_value x_values)
                            x_values = cons(x_value x_values)
                        )
                        unless(member(y_value y_values)
                            y_values = cons(y_value y_values)
                        )
                        net = fsp_pin_net(pin)
                        net_label = fsp_export_field(fsp_net_label(net))
                        color_index = fsp_net_custom_color_index(net)
                        entry = list(
                            fsp_export_field(fsp_pin_number(pin))
                            net_label
                            x_value
                            y_value
                            color_index
                        )
                        entries = cons(entry entries)
                    )
                )
            )
        )

        if(errors then
            list(nil reverse(errors))
        else
            if(!entries then
                list(nil list(sprintf(nil "%s \303\273\323\320\277\311\265\274\263\366\265\304\302\337\274\255\322\375\275\305\241\243" fsp_symbol_refdes(symbol))))
            else
                x_values = sort(x_values 'fsp_number_lessp)
                y_values = sort(y_values 'fsp_number_greaterp)
                list(
                    list(
                        fsp_export_field(fsp_symbol_refdes(symbol))
                        x_values
                        y_values
                        reverse(entries)
                    )
                    nil
                )
            )
        )
    )
)

defun( fsp_pinmap_layouts_for_symbols (symbols)
    let((layouts errors pin_count sorted_symbols symbol result layout messages message)
        layouts = nil
        errors = nil
        pin_count = 0
        sorted_symbols = sort(append(symbols nil) 'fsp_symbol_lessp)
        foreach(symbol sorted_symbols
            result = fsp_pinmap_layout_for_symbol(symbol)
            layout = nth(0 result)
            messages = nth(1 result)
            if(messages then
                foreach(message messages
                    errors = cons(message errors)
                )
            else
                layouts = cons(layout layouts)
                pin_count = pin_count + length(nth(3 layout))
            )
        )
        list(reverse(layouts) reverse(errors) pin_count)
    )
)

defun( fsp_pinmap_default_name (symbols)
    let((base stamp)
        if(length(symbols) == 1 then
            base = fsp_symbol_refdes(car(symbols))
        else
            base = fsp_export_field(axlCurrentDesign())
        )
        stamp = buildString(parseString(getCurrentTime() " :/") "")
        sprintf(nil "%s_pinmap_%s.xml" base stamp)
    )
)

defun( fsp_pinmap_bga_pin_parts (pin_number)
    let((row_parts column_parts)
        if(
            !stringp(pin_number) ||
            !rexMatchp("^[A-Za-z][A-Za-z]*[0-9][0-9]*$" pin_number)
        then
            nil
        else
            row_parts = parseString(pin_number "0123456789")
            column_parts = parseString(
                pin_number "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
            if(length(row_parts) == 1 && length(column_parts) == 1 then
                list(upperCase(car(row_parts)) car(column_parts))
            else
                nil
            )
        )
    )
)

defun( fsp_pinmap_bga_axis_labels (entries x_values y_values)
    let((valid x_labels y_labels x_value y_value entry parts label)
        valid = t
        x_labels = nil
        y_labels = nil

        foreach(x_value x_values
            label = nil
            foreach(entry entries
                when(nth(2 entry) == x_value
                    parts = fsp_pinmap_bga_pin_parts(nth(0 entry))
                    if(!parts then
                        valid = nil
                    else
                        if(!label then
                            label = nth(1 parts)
                        else
                            unless(equal(label nth(1 parts))
                                valid = nil
                            )
                        )
                    )
                )
            )
            when(!label || member(label x_labels)
                valid = nil
            )
            x_labels = append(x_labels list(label))
        )

        foreach(y_value y_values
            label = nil
            foreach(entry entries
                when(nth(3 entry) == y_value
                    parts = fsp_pinmap_bga_pin_parts(nth(0 entry))
                    if(!parts then
                        valid = nil
                    else
                        if(!label then
                            label = nth(0 parts)
                        else
                            unless(equal(label nth(0 parts))
                                valid = nil
                            )
                        )
                    )
                )
            )
            when(!label || member(label y_labels)
                valid = nil
            )
            y_labels = append(y_labels list(label))
        )

        if(valid then list(x_labels y_labels) else nil)
    )
)

defun( fsp_pinmap_non_bga_edge_candidate (entry entries side)
    let((candidate other x_value y_value other_x other_y)
        candidate = t
        x_value = nth(2 entry)
        y_value = nth(3 entry)
        foreach(other entries
            other_x = nth(2 other)
            other_y = nth(3 other)
            when(
                (equal(side "top") && other_x == x_value && other_y > y_value) ||
                (equal(side "right") && other_y == y_value && other_x > x_value) ||
                (equal(side "bottom") && other_x == x_value && other_y < y_value) ||
                (equal(side "left") && other_y == y_value && other_x < x_value)
                candidate = nil
            )
        )
        candidate
    )
)

defun( fsp_pinmap_non_bga_side (entry entries min_x max_x min_y max_y)
    let((x_value y_value side min_distance distance candidate_side)
        x_value = nth(2 entry)
        y_value = nth(3 entry)
        side = nil
        min_distance = nil

        foreach(candidate_side list("top" "bottom" "right" "left")
            when(fsp_pinmap_non_bga_edge_candidate(entry entries candidate_side)
                distance = cond(
                    (equal(candidate_side "top") max_y - y_value)
                    (equal(candidate_side "right") max_x - x_value)
                    (equal(candidate_side "bottom") y_value - min_y)
                    (t x_value - min_x)
                )
                when(!min_distance || distance < min_distance
                    side = candidate_side
                    min_distance = distance
                )
            )
        )
        side
    )
)

defun( fsp_pinmap_non_bga_axis_label
    (entries coordinate side min_x max_x min_y max_y)
    let((labels entry matches_axis)
        labels = nil
        foreach(entry entries
            matches_axis = if(
                equal(side "top") || equal(side "bottom")
                then nth(2 entry) == coordinate
                else nth(3 entry) == coordinate
            )
            when(
                matches_axis &&
                equal(
                    fsp_pinmap_non_bga_side(entry entries min_x max_x min_y max_y)
                    side
                )
                labels = append(labels list(nth(0 entry)))
            )
        )
        if(labels then buildString(labels "\n") else "")
    )
)

defun( fsp_define_pinmap_spreadsheet_styles ()
    axlSpreadsheetSetStyle("Default" nil)
    axlSpreadsheetSetStyleProp("Alignment" "Vertical" "Center")
    axlSpreadsheetSetStyleProp("Alignment" "Horizontal" "Center")
    axlSpreadsheetSetStyleProp("Alignment" "WrapText" "1")

    axlSpreadsheetSetStyle("AxisHeader" "Ball Map Axis")
    axlSpreadsheetSetStyleParent("Default")

    axlSpreadsheetSetStyle("PinCell" "Physical Pin")
    axlSpreadsheetSetStyleParent("Default")
    axlSpreadsheetSetStyleBorder("Left" "BLACK" "Continuous" "1")
    axlSpreadsheetSetStyleBorder("Right" "BLACK" "Continuous" "1")
    axlSpreadsheetSetStyleBorder("Top" "BLACK" "Continuous" "1")
    axlSpreadsheetSetStyleBorder("Bottom" "BLACK" "Continuous" "1")
    axlSpreadsheetSetStyleProp(
        "Fill" "Color" axlSpreadsheetGetRGBColorString(226 239 218))
    axlSpreadsheetSetStyleProp("Fill" "Pattern" "Solid")

    axlSpreadsheetSetStyle("EmptyCell" "Empty Physical Position")
    axlSpreadsheetSetStyleParent("Default")
    axlSpreadsheetSetStyleBorder("Left" "SILVER" "Continuous" "1")
    axlSpreadsheetSetStyleBorder("Right" "SILVER" "Continuous" "1")
    axlSpreadsheetSetStyleBorder("Top" "SILVER" "Continuous" "1")
    axlSpreadsheetSetStyleBorder("Bottom" "SILVER" "Continuous" "1")
    t
)

defun( fsp_define_pinmap_net_color_styles (layouts)
    let((styles seen layout entry color_index color_result rgb style_name)
        styles = nil
        seen = nil
        when(_fsp_export_net_colors
            foreach(layout layouts
                foreach(entry nth(3 layout)
                    color_index = nth(4 entry)
                    when(numberp(color_index) && !member(color_index seen)
                        seen = cons(color_index seen)
                        color_result = errset(axlColorGet(color_index) nil)
                        when(
                            color_result &&
                            listp(car(color_result)) &&
                            length(car(color_result)) >= 3
                            rgb = car(color_result)
                            when(
                                numberp(nth(0 rgb)) &&
                                numberp(nth(1 rgb)) &&
                                numberp(nth(2 rgb))
                                style_name = sprintf(nil "NetColor_%d" color_index)
                                when(axlSpreadsheetSetStyle(
                                    style_name
                                    sprintf(nil "PCB Net Color %d" color_index)
                                )
                                    axlSpreadsheetSetStyleParent("PinCell")
                                    axlSpreadsheetSetStyleBorder("Left" "BLACK" "Continuous" "1")
                                    axlSpreadsheetSetStyleBorder("Right" "BLACK" "Continuous" "1")
                                    axlSpreadsheetSetStyleBorder("Top" "BLACK" "Continuous" "1")
                                    axlSpreadsheetSetStyleBorder("Bottom" "BLACK" "Continuous" "1")
                                    axlSpreadsheetSetStyleProp(
                                        "Fill"
                                        "Color"
                                        axlSpreadsheetGetRGBColorString(
                                            nth(0 rgb)
                                            nth(1 rgb)
                                            nth(2 rgb)
                                        )
                                    )
                                    axlSpreadsheetSetStyleProp("Fill" "Pattern" "Solid")
                                    styles = cons(list(color_index style_name) styles)
                                )
                            )
                        )
                    )
                )
            )
        )
        styles
    )
)

defun( fsp_pinmap_color_style (styles color_index)
    let((style item)
        style = nil
        when(numberp(color_index)
            foreach(item styles
                when(!style && car(item) == color_index
                    style = cadr(item)
                )
            )
        )
        style
    )
)

defun( fsp_write_pinmap_file (file_name layouts)
    let((layout refdes x_values y_values entries x_value y_value entry row column value
         color_styles cell_style ok data_row data_column bottom_header_row
         right_header_column bga_axis_labels x_axis_labels y_axis_labels
         top_label bottom_label left_label right_label min_x max_x min_y max_y
         complete_grid_layout two_column_grid_layout two_row_grid_layout
         left_entry right_entry top_entry bottom_entry)
        ok = nil
        if(!axlSpreadsheetInit() then
            nil
        else
            unwindProtect(
                progn(
                    axlSpreadsheetSetDocProp("AUTHOR" "Moka skill - Pin Swap")
                    axlSpreadsheetSetDocProp("VERSION" "Physical Pinmap v5")
                    fsp_define_pinmap_spreadsheet_styles()
                    color_styles = fsp_define_pinmap_net_color_styles(layouts)

                    foreach(layout layouts
                        refdes = nth(0 layout)
                        x_values = nth(1 layout)
                        y_values = nth(2 layout)
                        entries = nth(3 layout)
                        bga_axis_labels = fsp_pinmap_bga_axis_labels(
                            entries x_values y_values)
                        complete_grid_layout = !bga_axis_labels &&
                            fsp_pinmap_complete_grid_p(entries x_values y_values)
                        two_column_grid_layout = !bga_axis_labels &&
                            length(x_values) == 2 &&
                            complete_grid_layout
                        two_row_grid_layout = !two_column_grid_layout &&
                            length(y_values) == 2 &&
                            complete_grid_layout
                        x_axis_labels = if(bga_axis_labels then nth(0 bga_axis_labels) else nil)
                        y_axis_labels = if(bga_axis_labels then nth(1 bga_axis_labels) else nil)
                        when(
                            !bga_axis_labels &&
                            !two_column_grid_layout &&
                            !two_row_grid_layout
                            min_x = nth(0 x_values)
                            max_x = nth(length(x_values) - 1 x_values)
                            max_y = nth(0 y_values)
                            min_y = nth(length(y_values) - 1 y_values)
                        )
                        axlSpreadsheetSetWorksheet(refdes)
                        if(two_column_grid_layout then
                            for(column 1 4
                                axlSpreadsheetSetColumnProp(column "WIDTH" "72")
                                axlSpreadsheetSetColumnProp(column "AUTO_WIDTH" "0")
                            )
                            for(row 1 length(y_values)
                                axlSpreadsheetSetRowProp(row "HEIGHT" "72")
                                axlSpreadsheetSetRowProp(row "AUTO_HEIGHT" "0")
                                y_value = nth(row - 1 y_values)
                                left_entry = fsp_pinmap_layout_entry_at(
                                    entries nth(0 x_values) y_value)
                                right_entry = fsp_pinmap_layout_entry_at(
                                    entries nth(1 x_values) y_value)

                                axlSpreadsheetDefineCell(
                                    row 1 "AxisHeader" "String" nth(0 left_entry))
                                value = nth(1 left_entry)
                                cell_style = fsp_pinmap_color_style(
                                    color_styles nth(4 left_entry))
                                unless(cell_style
                                    cell_style = "PinCell"
                                )
                                axlSpreadsheetDefineCell(
                                    row 2 cell_style "String" value)

                                value = nth(1 right_entry)
                                cell_style = fsp_pinmap_color_style(
                                    color_styles nth(4 right_entry))
                                unless(cell_style
                                    cell_style = "PinCell"
                                )
                                axlSpreadsheetDefineCell(
                                    row 3 cell_style "String" value)
                                axlSpreadsheetDefineCell(
                                    row 4 "AxisHeader" "String" nth(0 right_entry))
                            )
                        else if(two_row_grid_layout then
                            for(column 1 length(x_values)
                                axlSpreadsheetSetColumnProp(column "WIDTH" "72")
                                axlSpreadsheetSetColumnProp(column "AUTO_WIDTH" "0")
                            )
                            for(row 1 4
                                axlSpreadsheetSetRowProp(row "HEIGHT" "72")
                                axlSpreadsheetSetRowProp(row "AUTO_HEIGHT" "0")
                            )
                            for(column 1 length(x_values)
                                x_value = nth(column - 1 x_values)
                                top_entry = fsp_pinmap_layout_entry_at(
                                    entries x_value nth(0 y_values))
                                bottom_entry = fsp_pinmap_layout_entry_at(
                                    entries x_value nth(1 y_values))

                                axlSpreadsheetDefineCell(
                                    1 column "AxisHeader" "String" nth(0 top_entry))
                                value = nth(1 top_entry)
                                cell_style = fsp_pinmap_color_style(
                                    color_styles nth(4 top_entry))
                                unless(cell_style
                                    cell_style = "PinCell"
                                )
                                axlSpreadsheetDefineCell(
                                    2 column cell_style "String" value)

                                value = nth(1 bottom_entry)
                                cell_style = fsp_pinmap_color_style(
                                    color_styles nth(4 bottom_entry))
                                unless(cell_style
                                    cell_style = "PinCell"
                                )
                                axlSpreadsheetDefineCell(
                                    3 column cell_style "String" value)
                                axlSpreadsheetDefineCell(
                                    4 column "AxisHeader" "String" nth(0 bottom_entry))
                            )
                        else
                            bottom_header_row = length(y_values) + 2
                            right_header_column = length(x_values) + 2

                            for(column 1 right_header_column
                                axlSpreadsheetSetColumnProp(column "WIDTH" "72")
                                axlSpreadsheetSetColumnProp(column "AUTO_WIDTH" "0")
                            )
                            for(row 1 bottom_header_row
                                axlSpreadsheetSetRowProp(row "HEIGHT" "72")
                                axlSpreadsheetSetRowProp(row "AUTO_HEIGHT" "0")
                            )
                            axlSpreadsheetDefineCell(1 1 "AxisHeader" "String" "")
                            axlSpreadsheetDefineCell(1 right_header_column "AxisHeader" "String" "")
                            axlSpreadsheetDefineCell(bottom_header_row 1 "AxisHeader" "String" "")
                            axlSpreadsheetDefineCell(
                                bottom_header_row right_header_column "AxisHeader" "String" "")

                            for(column 1 length(x_values)
                                data_column = column + 1
                                x_value = nth(column - 1 x_values)
                                if(bga_axis_labels then
                                    top_label = nth(column - 1 x_axis_labels)
                                    bottom_label = top_label
                                else
                                    top_label = fsp_pinmap_non_bga_axis_label(
                                        entries x_value "top" min_x max_x min_y max_y)
                                    bottom_label = fsp_pinmap_non_bga_axis_label(
                                        entries x_value "bottom" min_x max_x min_y max_y)
                                )
                                axlSpreadsheetDefineCell(
                                    1 data_column "AxisHeader" "String" top_label)
                                axlSpreadsheetDefineCell(
                                    bottom_header_row data_column "AxisHeader" "String" bottom_label)
                            )

                            for(row 1 length(y_values)
                                data_row = row + 1
                                y_value = nth(row - 1 y_values)
                                if(bga_axis_labels then
                                    left_label = nth(row - 1 y_axis_labels)
                                    right_label = left_label
                                else
                                    left_label = fsp_pinmap_non_bga_axis_label(
                                        entries y_value "left" min_x max_x min_y max_y)
                                    right_label = fsp_pinmap_non_bga_axis_label(
                                        entries y_value "right" min_x max_x min_y max_y)
                                )
                                axlSpreadsheetDefineCell(
                                    data_row 1 "AxisHeader" "String" left_label)
                                axlSpreadsheetDefineCell(
                                    data_row right_header_column "AxisHeader" "String" right_label)
                                for(column 1 length(x_values)
                                    data_column = column + 1
                                    x_value = nth(column - 1 x_values)
                                    entry = fsp_pinmap_layout_entry_at(entries x_value y_value)
                                    if(entry then
                                        value = nth(1 entry)
                                        cell_style = fsp_pinmap_color_style(
                                            color_styles nth(4 entry))
                                        unless(cell_style
                                            cell_style = "PinCell"
                                        )
                                        axlSpreadsheetDefineCell(
                                            data_row data_column cell_style "String" value)
                                    else
                                        axlSpreadsheetDefineCell(
                                            data_row data_column "EmptyCell" "String" "")
                                    )
                                )
                            )
                        ))

                    )
                    ok = axlSpreadsheetWrite(file_name)
                )
                axlSpreadsheetClose()
            )
        )
        ok
    )
)

defun( fsp_pinmap_error_summary (errors)
    let((lines count message)
        lines = nil
        count = 0
        foreach(message errors
            when(count < 8
                lines = append(lines list(message))
            )
            count = count + 1
        )
        when(count > 8
            lines = append(lines list(sprintf(nil "... \273\271\323\320 %d \270\366\264\355\316\363\241\243" count - 8)))
        )
        buildString(lines "\n")
    )
)

defun( fsp_parse_pinmap_cell (cell_data)
    let((tokens target_net)
        if(!stringp(cell_data) || strlen(cell_data) == 0 then
            list(nil "Pin \265\245\324\252\270\361\326\320\265\304\315\370\302\347\316\252\277\325\241\243")
        else
            tokens = parseString(cell_data "\r\n")
            if(length(tokens) != 1 then
                list(nil "Pin \265\245\324\252\270\361\326\320\326\273\304\334\260\374\272\254\322\273\320\320\315\370\302\347\303\373\241\243")
            else
                target_net = nth(0 tokens)
                if(strlen(target_net) == 0 then
                    list(nil "Pin \265\245\324\252\270\361\326\320\265\304\315\370\302\347\316\252\277\325\241\243")
                else
                    list(target_net nil)
                )
            )
        )
    )
)

defun( fsp_read_pinmap_file (file_name)
    let((rows errors worksheets worksheet component symbol layout_result layout layout_errors message
         x_values y_values entries size expected_rows expected_columns row column x_value y_value
         entry cell cell_data parsed pin_number target_net parse_error location current_net result
         actual_row actual_column bga_axis_labels complete_grid_layout
         two_column_grid_layout two_row_grid_layout)
        rows = nil
        errors = nil
        result = nil

        if(!axlSpreadsheetRead(file_name) then
            list(nil list(sprintf(nil "\316\336\267\250\266\301\310\241\316\357\300\355 Pinmap \271\244\327\367\262\276\243\272%s" file_name)))
        else
            unwindProtect(
                progn(
                    worksheets = axlSpreadsheetGetWorksheets()
                    if(!worksheets then
                        errors = list("\316\357\300\355 Pinmap \271\244\327\367\262\276\326\320\303\273\323\320\306\367\274\376\271\244\327\367\261\355\241\243")
                    else
                        foreach(worksheet worksheets
                            component = axlDBFindByName('refdes worksheet)
                            symbol = fsp_normalize_symbol(component)
                            if(!symbol then
                                errors = append(
                                    errors
                                    list(sprintf(nil "\271\244\327\367\261\355 %s \323\353\322\321\267\305\326\303\306\367\274\376\262\273\306\245\305\344\241\243" worksheet))
                                )
                            else
                                layout_result = fsp_pinmap_layout_for_symbol(symbol)
                                layout = nth(0 layout_result)
                                layout_errors = nth(1 layout_result)
                                if(layout_errors then
                                    foreach(message layout_errors
                                        errors = append(errors list(message))
                                    )
                                else
                                    axlSpreadsheetSetWorksheet(worksheet)
                                    x_values = nth(1 layout)
                                    y_values = nth(2 layout)
                                    entries = nth(3 layout)
                                    bga_axis_labels = fsp_pinmap_bga_axis_labels(
                                        entries x_values y_values)
                                    complete_grid_layout = !bga_axis_labels &&
                                        fsp_pinmap_complete_grid_p(
                                            entries x_values y_values)
                                    two_column_grid_layout = !bga_axis_labels &&
                                        length(x_values) == 2 &&
                                        complete_grid_layout
                                    two_row_grid_layout = !two_column_grid_layout &&
                                        length(y_values) == 2 &&
                                        complete_grid_layout
                                    expected_rows = length(y_values)
                                    expected_columns = length(x_values)
                                    size = axlSpreadsheetGetWorksheetSize()

                                    if(
                                        !size ||
                                        (two_column_grid_layout &&
                                            (nth(0 size) != expected_rows ||
                                             nth(1 size) != 4)) ||
                                        (two_row_grid_layout &&
                                            (nth(0 size) != 4 ||
                                             nth(1 size) != expected_columns)) ||
                                        (!two_column_grid_layout &&
                                         !two_row_grid_layout &&
                                            (nth(0 size) != expected_rows + 2 ||
                                             nth(1 size) != expected_columns + 2))
                                    then
                                        errors = append(
                                            errors
                                            list(
                                                sprintf(
                                                    nil
                                                    "\271\244\327\367\261\355 %s \265\304\264\363\320\241\323\353\267\342\327\260\316\357\300\355\262\274\276\326\262\273\306\245\305\344\241\243"
                                                    worksheet
                                                )
                                            )
                                        )
                                    else
                                        for(row 1 expected_rows
                                            actual_row = if(
                                                two_column_grid_layout then
                                                    row
                                                else
                                                    row + 1
                                            )
                                            y_value = nth(row - 1 y_values)
                                            for(column 1 expected_columns
                                                actual_column = if(
                                                    two_row_grid_layout then
                                                        column
                                                    else
                                                        column + 1
                                                )
                                                x_value = nth(column - 1 x_values)
                                                entry = fsp_pinmap_layout_entry_at(entries x_value y_value)
                                                cell = axlSpreadsheetGetCell(actual_row actual_column)
                                                cell_data = if(
                                                    cell && stringp(cell->data)
                                                    then cell->data
                                                    else ""
                                                )
                                                location = sprintf(
                                                    nil "%s!R%dC%d" worksheet actual_row actual_column)

                                                if(entry then
                                                    parsed = fsp_parse_pinmap_cell(cell_data)
                                                    target_net = nth(0 parsed)
                                                    parse_error = nth(1 parsed)
                                                    if(parse_error then
                                                        errors = append(
                                                            errors
                                                            list(sprintf(nil "%s: %s" location parse_error))
                                                        )
                                                    else
                                                        pin_number = nth(0 entry)
                                                        current_net = nth(1 entry)
                                                        rows = cons(
                                                            list(
                                                                worksheet
                                                                pin_number
                                                                current_net
                                                                target_net
                                                                location
                                                                nth(2 entry)
                                                                nth(3 entry)
                                                            )
                                                            rows
                                                        )
                                                    )
                                                else
                                                    when(strlen(cell_data) > 0
                                                        errors = append(
                                                            errors
                                                            list(
                                                                sprintf(
                                                                    nil
                                                                    "%s \312\307\277\325\316\357\300\355\316\273\326\303\243\254\261\330\320\353\261\243\263\326\316\252\277\325\241\243"
                                                                    location
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                    result = list(reverse(rows) errors)
                )
                axlSpreadsheetClose()
            )
            result
        )
    )
)
defun( fsp_find_symbol_pin (symbol pin_number)
    let((result pin)
        result = nil
        when(symbol && symbol->pins
            foreach(pin symbol->pins
                when(!result && equal(fsp_pin_number(pin) pin_number)
                    result = pin
                )
            )
        )
        result
    )
)

defun( fsp_symbol_logical_pin_count (symbol)
    let((count pin)
        count = 0
        when(symbol && symbol->pins
            foreach(pin symbol->pins
                when(pin->objType == "pin" && !pin->isMech && pin->number
                    count = count + 1
                )
            )
        )
        count
    )
)

defun( fsp_pinmap_refdes_row_count (rows refdes)
    let((count row)
        count = 0
        foreach(row rows
            when(equal(nth(0 row) refdes)
                count = count + 1
            )
        )
        count
    )
)

defun( fsp_pinmap_value_count (rows refdes field_index value)
    let((count row)
        count = 0
        foreach(row rows
            when(equal(nth(0 row) refdes) && equal(nth(field_index row) value)
                count = count + 1
            )
        )
        count
    )
)

defun( fsp_pinmap_permutation_valid (rows refdes)
    let((labels row label ok)
        labels = nil
        ok = t
        foreach(row rows
            when(equal(nth(0 row) refdes)
                label = nth(2 row)
                unless(member(label labels)
                    labels = cons(label labels)
                )
                label = nth(3 row)
                unless(member(label labels)
                    labels = cons(label labels)
                )
            )
        )
        foreach(label labels
            unless(
                fsp_pinmap_value_count(rows refdes 2 label) ==
                fsp_pinmap_value_count(rows refdes 3 label)
                ok = nil
            )
        )
        ok
    )
)

defun( fsp_validate_pinmap_rows (raw_rows)
    let((rows errors keys refdeses raw source_location refdes pin_number before_net target_net
         component symbol pin current_net current_label target_db target_label key row_ok
         file_x file_y local_xy actual_x actual_y imported_count actual_count)
        rows = nil
        errors = nil
        keys = nil
        refdeses = nil

        foreach(raw raw_rows
            refdes = nth(0 raw)
            pin_number = nth(1 raw)
            before_net = nth(2 raw)
            target_net = nth(3 raw)
            source_location = nth(4 raw)
            file_x = nth(5 raw)
            file_y = nth(6 raw)
            row_ok = t
            component = axlDBFindByName('refdes refdes)
            symbol = fsp_normalize_symbol(component)

            if(!symbol then
                errors = cons(sprintf(nil "%s\243\272\316\264\325\322\265\275\306\367\274\376 %s\241\243" source_location refdes) errors)
                row_ok = nil
            )

            when(row_ok
                refdes = fsp_symbol_refdes(symbol)
                pin = fsp_find_symbol_pin(symbol pin_number)
                if(!pin || pin->isMech then
                    errors = cons(
                        sprintf(nil "%s\243\272\316\264\325\322\265\275 Pin %s.%s\243\254\273\362\270\303 Pin \316\252\273\372\320\265\322\375\275\305\241\243" source_location refdes pin_number)
                        errors
                    )
                    row_ok = nil
                )
            )

            when(row_ok
                pin_number = fsp_pin_number(pin)
                key = sprintf(nil "%s\t%s" refdes pin_number)
                if(member(key keys) then
                    errors = cons(sprintf(nil "%s\243\272Pin %s.%s \326\330\270\264\241\243" source_location refdes pin_number) errors)
                    row_ok = nil
                else
                    keys = cons(key keys)
                )
            )

            when(row_ok
                local_xy = fsp_pinmap_local_xy(pin)
                if(!local_xy then
                    errors = cons(
                        sprintf(nil "%s\243\272%s.%s \303\273\323\320\306\367\274\376\261\276\265\330\327\370\261\352\241\243"
                            source_location refdes pin_number)
                        errors
                    )
                    row_ok = nil
                else
                    actual_x = car(local_xy)
                    actual_y = cadr(local_xy)
                    if(abs(actual_x - file_x) > 0.0005 || abs(actual_y - file_y) > 0.0005 then
                        errors = cons(
                            sprintf(
                                nil
                                "%s\243\272%s.%s \265\304\262\274\276\326\327\370\261\352\323\353\322\321\267\305\326\303\267\342\327\260\262\273\306\245\305\344\241\243"
                                source_location refdes pin_number
                            )
                            errors
                        )
                        row_ok = nil
                    )
                )
            )

            when(row_ok
                current_net = fsp_pin_net(pin)
                current_label = fsp_net_label(current_net)
                if(!equal(before_net current_label) then
                    errors = cons(
                        sprintf(
                            nil
                            "%s\243\272Pinmap \320\243\321\351\306\332\274\344 %s.%s \265\304 PCB \315\370\302\347\267\242\311\372\261\344\273\257\241\243"
                            source_location refdes pin_number
                        )
                        errors
                    )
                    row_ok = nil
                )
            )

            when(row_ok
                if(equal(target_net "<UNCONNECTED>") then
                    target_db = nil
                    target_label = "<UNCONNECTED>"
                else
                    target_db = axlDBFindByName('net target_net)
                    if(!target_db then
                        errors = cons(
                            sprintf(nil "%s\243\272\316\264\325\322\265\275\304\277\261\352\315\370\302\347 %s\241\243" source_location target_net)
                            errors
                        )
                        row_ok = nil
                    else
                        target_label = fsp_net_label(target_db)
                    )
                )
            )

            when(row_ok
                rows = cons(
                    list(refdes pin_number current_label target_label pin current_net target_db)
                    rows
                )
                unless(member(refdes refdeses)
                    refdeses = cons(refdes refdeses)
                )
            )
        )

        rows = reverse(rows)
        when(!errors
            foreach(refdes refdeses
                component = axlDBFindByName('refdes refdes)
                symbol = fsp_normalize_symbol(component)
                imported_count = fsp_pinmap_refdes_row_count(rows refdes)
                actual_count = fsp_symbol_logical_pin_count(symbol)
                unless(imported_count == actual_count
                    errors = cons(
                        sprintf(nil "%s\243\272Pinmap \260\374\272\254 %d \270\366\322\375\275\305\243\254\265\253\267\342\327\260\260\374\272\254 %d \270\366\241\243"
                            refdes imported_count actual_count)
                        errors
                    )
                )
                unless(fsp_pinmap_permutation_valid(rows refdes)
                    errors = cons(
                        sprintf(
                            nil
                            "%s\243\272\265\261\307\260\315\370\302\347\323\353\265\274\310\353\315\370\302\347\265\304\312\375\301\277\316\336\267\250\271\271\263\311\315\352\325\373\265\304\322\375\275\305\305\305\301\320\241\243"
                            refdes
                        )
                        errors
                    )
                )
            )
        )
        list(rows reverse(errors) length(refdeses))
    )
)

defun( fsp_pinmap_changed_count (rows)
    let((count row)
        count = 0
        foreach(row rows
            unless(equal(nth(2 row) nth(3 row))
                count = count + 1
            )
        )
        count
    )
)

defun( fsp_apply_pinmap_rows (rows)
    let((mark row result ok mappings mapping pin_label change_count)
        mark = axlDBTransactionStart()
        ok = mark
        mappings = nil
        change_count = fsp_pinmap_changed_count(rows)

        if(!mark then
            fsp_ui_set_status("\316\336\267\250\306\364\266\257 Pinmap \305\372\301\277\312\302\316\361\241\243")
            nil
        else
            foreach(row rows
                when(ok && !equal(nth(2 row) nth(3 row))
                    result = errset(axlDBAssignNet(nth(4 row) nth(6 row) nil t) nil)
                    if(result && car(result) then
                        pin_label = sprintf(nil "%s.%s" nth(0 row) nth(1 row))
                        mapping = list(
                            sprintf(nil "%s %s" pin_label fsp_export_field(nth(2 row)))
                            sprintf(nil "%s %s" pin_label fsp_export_field(nth(3 row)))
                        )
                        mappings = cons(mapping mappings)
                    else
                        ok = nil
                    )
                )
            )

            if(ok && axlDBTransactionCommit(mark) then
                mappings = reverse(mappings)
                when(mappings
                    _fsp_export_records = cons(mappings _fsp_export_records)
                )
                axlMsgPut(sprintf(nil "Moka skill - Pin Swap: Pinmap \322\321\323\246\323\303 %d \270\366\322\375\275\305\261\344\270\374\241\243" change_count))
                fsp_ui_set_status(sprintf(nil "Pinmap \322\321\323\246\323\303\243\272%d \270\366\322\375\275\305\261\344\270\374\243\254\277\311\322\324\265\274\263\366\310\325\326\276\241\243" change_count))
                t
            else
                errset(axlDBTransactionRollback(mark) nil)
                axlMsgPut("Moka skill - Pin Swap: Pinmap \305\372\301\277\323\246\323\303\312\247\260\334\243\254\313\371\323\320\270\374\270\304\322\321\273\330\271\366\241\243")
                fsp_ui_set_status("Pinmap \305\372\301\277\323\246\323\303\312\247\260\334\243\254\313\371\323\320\270\374\270\304\322\321\273\330\271\366\241\243")
                nil
            )
        )
    )
)

defun( fsp_pinmap_clear_highlights ()
    let((symbol)
        foreach(symbol _fsp_pinmap_highlights
            errset(axlDehighlightObject(symbol t) nil)
        )
        _fsp_pinmap_highlights = nil
    )
)

defun( fsp_pinmap_collect_symbols (symbols selected)
    let((object symbol)
        foreach(object selected
            symbol = fsp_normalize_symbol(object)
            when(symbol && !memq(symbol symbols)
                symbols = cons(symbol symbols)
                _fsp_pinmap_highlights = cons(symbol _fsp_pinmap_highlights)
                errset(axlHighlightObject(symbol t) nil)
            )
        )
        symbols
    )
)

defun( fsp_pinmap_export_cmd ()
    let((popup symbols selected layout_result layouts errors pin_count file_name)
        _fsp_pinmap_active = t
        _fsp_pinmap_finished = nil
        _fsp_pinmap_cancelled = nil
        _fsp_pinmap_highlights = nil
        symbols = nil

        fsp_ui_set_status("\321\241\324\361\322\252\265\274\263\366 Pinmap \265\304\306\367\274\376\243\254\315\352\263\311\272\363\323\322\274\374 Done\241\243")
        popup = axlUIPopupDefine(
            nil
            list(
                list("Done" 'fsp_pinmap_cb_done)
                list("Cancel" 'fsp_pinmap_cb_cancel)
            )
        )
        axlUIPopupSet(popup)

        unwindProtect(
            progn(
                while(!_fsp_pinmap_finished
                    axlClearSelSet()
                    axlSetFindFilter(
                        ?enabled list("noall" "components" "symbols")
                        ?onButtons list("noall" "components" "symbols")
                    )
                    if(
                        axlSelect(?prompt "\321\241\324\361\322\252\265\274\263\366 Pinmap \265\304\306\367\274\376\241\243\315\352\263\311\272\363\323\322\274\374 Done\241\243")
                    then
                        selected = axlGetSelSet()
                        symbols = fsp_pinmap_collect_symbols(symbols selected)
                        fsp_ui_set_status(
                            sprintf(nil "\322\321\321\241\324\361 %d \270\366\306\367\274\376\243\254\277\311\274\314\320\370\321\241\324\361\273\362\265\343\273\367\241\260\315\352\263\311\241\261\241\243" length(symbols))
                        )
                    else
                        unless(_fsp_pinmap_finished
                            _fsp_pinmap_finished = t
                            _fsp_pinmap_cancelled = t
                        )
                    )
                )

                axlUIPopupSet(nil)
                unless(_fsp_pinmap_cancelled
                    if(!symbols then
                        fsp_ui_set_status("\316\264\321\241\324\361\322\252\265\274\263\366 Pinmap \265\304\306\367\274\376\241\243")
                    else
                        symbols = reverse(symbols)
                        layout_result = fsp_pinmap_layouts_for_symbols(symbols)
                        layouts = nth(0 layout_result)
                        errors = nth(1 layout_result)
                        pin_count = nth(2 layout_result)
                        if(errors then
                            axlUIConfirm(fsp_pinmap_error_summary(errors) 'error)
                            fsp_ui_set_status(sprintf(nil "\316\357\300\355 Pinmap \311\372\263\311\312\247\260\334\243\254\271\262 %d \270\366\264\355\316\363\241\243" length(errors)))
                        else
                            file_name = axlDMFileBrowse(
                                nil
                                t
                                ?defaultName fsp_pinmap_default_name(symbols)
                                ?title "\265\274\263\366\306\367\274\376\316\357\300\355 Pinmap"
                                ?optFilters "\316\357\300\355 Pinmap \271\244\327\367\262\276 (*.xml)|*.xml|"
                            )
                            if(!file_name then
                                fsp_ui_set_status("Pinmap \265\274\263\366\322\321\310\241\317\373\241\243")
                            else
                                if(fsp_write_pinmap_file(file_name layouts) then
                                    axlMsgPut(
                                        sprintf(
                                            nil
                                            "Moka skill - Pin Swap: \322\321\275\253 %d \270\366\322\375\275\305\265\304\316\357\300\355 Pinmap \265\274\263\366\265\275 %s\241\243"
                                            pin_count file_name
                                        )
                                    )
                                    fsp_ui_set_status(
                                        sprintf(nil "\322\321\265\274\263\366 %d \270\366\322\375\275\305\241\242%d \270\366\306\367\274\376\265\304\316\357\300\355 Pinmap\241\243"
                                            pin_count length(symbols))
                                    )
                                else
                                    fsp_ui_set_status("\316\336\267\250\320\264\310\353\316\357\300\355 Pinmap \316\304\274\376\241\243")
                                )
                            )
                        )
                    )
                )
            )
            progn(
                axlUIPopupSet(nil)
                axlClearSelSet()
                fsp_pinmap_clear_highlights()
                _fsp_pinmap_active = nil
                fsp_ui_close_if_pending()
            )
        )
    )
)

defun( fsp_pinmap_import_cmd ()
    let((file_name parsed raw_rows errors validated rows component_count change_count)
        _fsp_pinmap_active = t
        unwindProtect(
            progn(
                fsp_ui_set_status("\321\241\324\361\322\252\320\243\321\351\262\242\323\246\323\303\265\304\316\357\300\355 Pinmap \271\244\327\367\262\276\241\243")
                file_name = axlDMFileBrowse(
                    nil
                    nil
                    ?title "\265\274\310\353\262\242\323\246\323\303\306\367\274\376\316\357\300\355 Pinmap"
                    ?optFilters "\316\357\300\355 Pinmap \271\244\327\367\262\276 (*.xml)|*.xml|"
                )
                if(!file_name then
                    fsp_ui_set_status("Pinmap \265\274\310\353\322\321\310\241\317\373\241\243")
                else
                    parsed = fsp_read_pinmap_file(file_name)
                    raw_rows = nth(0 parsed)
                    errors = nth(1 parsed)
                    if(errors then
                        axlUIConfirm(fsp_pinmap_error_summary(errors) 'error)
                        fsp_ui_set_status(sprintf(nil "Pinmap \275\342\316\366\312\247\260\334\243\254\271\262 %d \270\366\264\355\316\363\241\243" length(errors)))
                    else
                        validated = fsp_validate_pinmap_rows(raw_rows)
                        rows = nth(0 validated)
                        errors = nth(1 validated)
                        component_count = nth(2 validated)
                        if(errors then
                            axlUIConfirm(fsp_pinmap_error_summary(errors) 'error)
                            fsp_ui_set_status(sprintf(nil "Pinmap \320\243\321\351\312\247\260\334\243\254\271\262 %d \270\366\264\355\316\363\241\243" length(errors)))
                        else
                            change_count = fsp_pinmap_changed_count(rows)
                            if(change_count == 0 then
                                fsp_ui_set_status("Pinmap \320\243\321\351\315\250\271\375\243\254\265\253\316\264\267\242\317\326\315\370\302\347\261\344\270\374\241\243")
                            else
                                if(
                                    axlUIYesNo(
                                        sprintf(
                                            nil
                                            "\312\307\267\361\275\253 %d \270\366\322\375\275\305\261\344\270\374\323\246\323\303\265\275 %d \270\366\306\367\274\376\243\277\324\255\301\254\275\323\317\337\275\253\261\243\301\364\243\254Pin \265\304 FIXED \327\264\314\254\275\253\261\273\272\366\302\324\241\243"
                                            change_count component_count
                                        )
                                        "\323\246\323\303\306\367\274\376 Pinmap"
                                        'no
                                    )
                                then
                                    fsp_apply_pinmap_rows(rows)
                                else
                                    fsp_ui_set_status("Pinmap \323\246\323\303\322\321\310\241\317\373\243\254\316\264\275\370\320\320\310\316\272\316\270\374\270\304\241\243")
                                )
                            )
                        )
                    )
                )
            )
            progn(
                _fsp_pinmap_active = nil
                fsp_ui_refresh()
                fsp_ui_close_if_pending()
            )
        )
    )
)

defun( fsp_ui_record_lines (record state)
    let((lines mapping)
        lines = nil
        foreach(mapping record
            lines = append(
                lines
                list(sprintf(nil "[%s] %s -> %s" state nth(0 mapping) nth(1 mapping)))
            )
        )
        lines
    )
)

defun( fsp_ui_record_items ()
    let((items record)
        items = nil
        foreach(record reverse(_fsp_export_records)
            items = append(items fsp_ui_record_lines(record "\322\321\314\341\275\273"))
        )
        foreach(record reverse(_fsp_session_records)
            items = append(items fsp_ui_record_lines(record "\265\261\307\260"))
        )
        if(items then
            items
        else
            list("<\324\335\316\336\273\273 Pin \320\305\317\242>")
        )
    )
)

defun( fsp_ui_refresh ()
    let((component first_pin pair_count list_items old_item new_item)
        when(_fsp_ui_form
            component = if(_fsp_symbol then fsp_symbol_refdes(_fsp_symbol) else "-")
            first_pin = if(
                _fsp_first_pin
                then sprintf(
                    nil
                    "%s [%s]"
                    fsp_pin_label(_fsp_first_pin)
                    fsp_net_label(fsp_pin_net(_fsp_first_pin))
                )
                else "-"
            )
            pair_count = fsp_records_change_count(_fsp_export_records) +
                fsp_records_change_count(_fsp_session_records)

            errset(axlFormSetField(_fsp_ui_form "status" _fsp_ui_status) nil)
            errset(axlFormSetField(_fsp_ui_form "component" component) nil)
            errset(axlFormSetField(_fsp_ui_form "first_pin" first_pin) nil)
            errset(axlFormSetField(_fsp_ui_form "record_count" sprintf(nil "%d" pair_count)) nil)

            list_items = fsp_ui_record_items()
            foreach(old_item _fsp_ui_list_items
                errset(axlFormListDeleteItem(_fsp_ui_form "swap_list" 0) nil)
            )
            foreach(new_item list_items
                errset(axlFormListAddItem(_fsp_ui_form "swap_list" new_item -1) nil)
            )
            _fsp_ui_list_items = list_items
        )
        t
    )
)

defun( fsp_ui_set_status (status_text)
    _fsp_ui_status = status_text
    when(status_text
        axlMsgPut(sprintf(nil "Moka skill - Pin Swap: %s" status_text))
    )
    fsp_ui_refresh()
)

defun( fsp_ui_busy ()
    _fsp_run_active || _fsp_pinmap_active
)

defun( fsp_panel_release_enter ()
    let((result)
        result = errset(axlCancelEnterFun() nil)
        unless(result && car(result)
            errset(axlFinishEnterFun() nil)
        )
        t
    )
)

defun( fsp_panel_schedule (action)
    _fsp_panel_action = action
    fsp_panel_release_enter()
)

defun( fsp_panel_stop ()
    _fsp_panel_active = nil
    fsp_panel_release_enter()
)

defun( fsp_panel_done ()
    if(_fsp_run_active then
        _fsp_ui_close_pending = t
        fsp_cb_done()
    else
        if(_fsp_pinmap_active then
            _fsp_ui_close_pending = t
            fsp_pinmap_cb_done()
        else
            _fsp_panel_active = nil
            errset(axlFinishEnterFun() nil)
        )
    )
    t
)

defun( fsp_panel_cancel ()
    if(_fsp_run_active then
        _fsp_ui_close_pending = t
        fsp_cb_cancel()
    else
        if(_fsp_pinmap_active then
            _fsp_ui_close_pending = t
            fsp_pinmap_cb_cancel()
        else
            fsp_panel_stop()
        )
    )
    t
)

defun( fsp_write_ui_form (form_file)
    let((port ok)
        ok = nil
        port = outfile(form_file)
        when(port
            fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\n")
            fprintf(port "FORM\nFIXED\nPORT 32 39\n")
            fprintf(port "HEADER \"Moka skill v%s - \273\273 Pin\"\n" _fsp_version)
            fprintf(port "TILE\n")
            fprintf(port "TEXT \"\306\367\274\376\243\272\"\nTLOC 1 1\nENDTEXT\n")
            fprintf(port "FIELD component\nFLOC 10 1\nSTRFILLIN 17 80\nENDFIELD\n")
            fprintf(port "TEXT \"\265\332\322\273\322\375\275\305\243\272\"\nTLOC 1 3\nENDTEXT\n")
            fprintf(port "FIELD first_pin\nFLOC 10 3\nSTRFILLIN 17 120\nENDFIELD\n")
            fprintf(port "TEXT \"\322\375\275\305\261\344\270\374\243\272\"\nTLOC 1 5\nENDTEXT\n")
            fprintf(port "FIELD record_count\nFLOC 10 5\nSTRFILLIN 6 12\nENDFIELD\n")
            fprintf(port "FIELD swap_list\nFLOC 1 7\nLIST \"\" 27 5\nENDFIELD\n")
            fprintf(port "FIELD btn_start\nFLOC 1 17\nMENUBUTTON \"\277\252\312\274\273\273 Pin\" 12 3\nENDFIELD\n")
            fprintf(port "FIELD btn_finish\nFLOC 15 17\nMENUBUTTON \"\315\352\263\311\" 12 3\nENDFIELD\n")
            fprintf(port "FIELD btn_oops\nFLOC 1 20\nMENUBUTTON \"Oops\" 8 3\nENDFIELD\n")
            fprintf(port "FIELD btn_cancel\nFLOC 11 20\nMENUBUTTON \"\310\241\317\373\262\331\327\367\" 16 3\nENDFIELD\n")
            fprintf(port "FIELD btn_export\nFLOC 1 23\nMENUBUTTON \"\265\274\263\366\310\325\326\276\" 12 3\nENDFIELD\n")
            fprintf(port "FIELD btn_clear\nFLOC 15 23\nMENUBUTTON \"\307\345\277\325\310\325\326\276\" 12 3\nENDFIELD\n")
            fprintf(port "TEXT \"Pinmap\"\nTLOC 1 26\nOPTIONS BOLD\nENDTEXT\n")
            fprintf(port "FIELD pinmap_net_colors\nFLOC 1 28\nCHECKLIST \"\265\274\263\366\315\370\302\347\321\325\311\253\"\nENDFIELD\n")
            fprintf(port "FIELD btn_pinmap_export\nFLOC 1 30\nMENUBUTTON \"\265\274\263\366 Pinmap\" 27 3\nENDFIELD\n")
            fprintf(port "FIELD btn_pinmap_import\nFLOC 1 33\nMENUBUTTON \"\265\274\310\353\262\242\323\246\323\303\" 27 3\nENDFIELD\n")
            fprintf(port "FIELD done\nFLOC 20 36\nMENUBUTTON \"\271\330\261\325\" 9 3\nENDFIELD\n")
            fprintf(port "ENDTILE\n")
            fprintf(port "ENDFORM\n")
            close(port)
            ok = t
        )
        ok
    )
)

defun( fsp_ui_request_close (form)
    if(_fsp_run_active then
        _fsp_ui_close_pending = t
        fsp_cb_cancel()
    else
        if(_fsp_pinmap_active then
            _fsp_ui_close_pending = t
            fsp_pinmap_cb_cancel()
        else
            if(_fsp_panel_active then
                fsp_panel_stop()
            else
                _fsp_ui_form = nil
                _fsp_ui_list_items = nil
                errset(axlFormClose(form) nil)
            )
        )
    )
)

defun( fsp_ui_form_cb (form)
    let((field)
        if(form->doneState > 0 then
            fsp_ui_request_close(form)
        else
            field = form->curField
            case(field
                ("btn_start"
                    if(fsp_ui_busy() then
                        fsp_ui_set_status("\307\353\317\310\315\352\263\311\273\362\310\241\317\373\265\261\307\260\262\331\327\367\241\243")
                    else
                        fsp_ui_set_status("\325\375\324\332\277\252\312\274\321\241\324\361\322\375\275\305...")
                        fsp_panel_schedule("SWAP")
                    )
                )
                ("btn_finish"
                    if(_fsp_run_active then
                        fsp_cb_done()
                    else
                        if(_fsp_pinmap_active then
                            fsp_pinmap_cb_done()
                        else
                            fsp_ui_set_status("\265\261\307\260\303\273\323\320\325\375\324\332\326\264\320\320\265\304\262\331\327\367\241\243")
                        )
                    )
                )
                ("btn_cancel"
                    if(_fsp_run_active then
                        fsp_cb_cancel()
                    else
                        if(_fsp_pinmap_active then
                            fsp_pinmap_cb_cancel()
                        else
                            fsp_ui_set_status("\265\261\307\260\303\273\323\320\325\375\324\332\326\264\320\320\265\304\262\331\327\367\241\243")
                        )
                    )
                )
                ("btn_oops"
                    if(_fsp_run_active then
                        fsp_cb_oops()
                    else
                        fsp_ui_set_status("\265\261\307\260\303\273\323\320\325\375\324\332\326\264\320\320\265\304\262\331\327\367\241\243")
                    )
                )
                ("btn_export"
                    if(fsp_ui_busy() then
                        fsp_ui_set_status("\307\353\317\310\315\352\263\311\273\362\310\241\317\373\265\261\307\260\262\331\327\367\243\254\324\331\265\274\263\366\310\325\326\276\241\243")
                    else
                        fsp_export_pending()
                    )
                )
                ("btn_clear"
                    if(fsp_ui_busy() then
                        fsp_ui_set_status("\307\353\317\310\315\352\263\311\273\362\310\241\317\373\265\261\307\260\262\331\327\367\243\254\324\331\307\345\277\325\310\325\326\276\241\243")
                    else
                        if(!_fsp_export_records then
                            fsp_ui_set_status("\303\273\323\320\277\311\307\345\277\325\265\304\322\321\314\341\275\273\273\273 Pin \320\305\317\242\241\243")
                        else
                            when(
                                axlUIYesNo(
                                    "\307\345\277\325\316\264\265\274\263\366\265\304\273\273 Pin \320\305\317\242\243\277PCB \270\374\270\304\262\273\273\341\273\330\315\313\241\243"
                                    "Moka skill - \273\273 Pin"
                                    'no
                                )
                                _fsp_export_records = nil
                                fsp_ui_set_status("\316\264\265\274\263\366\265\304\273\273 Pin \320\305\317\242\322\321\307\345\277\325\241\243")
                            )
                        )
                    )
                )
                ("btn_pinmap_export"
                    if(fsp_ui_busy() then
                        fsp_ui_set_status("\307\353\317\310\315\352\263\311\273\362\310\241\317\373\265\261\307\260\262\331\327\367\241\243")
                    else
                        _fsp_export_net_colors = if(
                            axlFormGetField(form "pinmap_net_colors")
                            then t
                            else nil
                        )
                        fsp_ui_set_status("\325\375\324\332\321\241\324\361\322\252\265\274\263\366 Pinmap \265\304\306\367\274\376...")
                        fsp_panel_schedule("PINMAP_EXPORT")
                    )
                )
                ("pinmap_net_colors"
                    _fsp_export_net_colors = if(
                        axlFormGetField(form "pinmap_net_colors")
                        then t
                        else nil
                    )
                )
                ("btn_pinmap_import"
                    if(fsp_ui_busy() then
                        fsp_ui_set_status("\307\353\317\310\315\352\263\311\273\362\310\241\317\373\265\261\307\260\262\331\327\367\241\243")
                    else
                        fsp_ui_set_status("\325\375\324\332\264\362\277\252 Pinmap \265\274\310\353...")
                        fsp_panel_schedule("PINMAP_IMPORT")
                    )
                )
            )
        )
        t
    )
)

defun( fsp_ui_open ()
    let((form_file form load_result point action saved_enabled saved_on)
        _fsp_panel_active = t
        _fsp_panel_action = nil
        _fsp_ui_ministatus = nil
        saved_enabled = axlGetFindFilter()
        saved_on = axlGetFindFilter(t)
        form_file = axlTempFile(t)
        if(fsp_write_ui_form(form_file) then
            when(isCallable('axlMiniStatusLoad)
                load_result = errset(
                    axlMiniStatusLoad((gensym) form_file 'fsp_ui_form_cb) nil)
                when(load_result && car(load_result)
                    form = car(load_result)
                    _fsp_ui_ministatus = t
                )
            )
            unless(form
                form = axlFormCreate(
                    (gensym)
                    form_file
                    list("E" "INNER" "WINDOW" "NOBORDER" "MSGLINES 0")
                    'fsp_ui_form_cb
                    t)
            )
            when(isFile(form_file) errset(axlTempFileRemove(form_file) nil))
            if(form then
                _fsp_ui_form = form
                _fsp_ui_list_items = nil
                errset(axlFormSetFieldEditable(form "component" nil) nil)
                errset(axlFormSetFieldEditable(form "first_pin" nil) nil)
                errset(axlFormSetFieldEditable(form "record_count" nil) nil)
                errset(axlFormSetField(form "pinmap_net_colors" _fsp_export_net_colors) nil)
                unless(_fsp_ui_ministatus axlFormDisplay(form))
                when(_fsp_ui_ministatus errset(axlControlRaise('options) nil))
                fsp_ui_refresh()
                unwindProtect(
                    while(_fsp_panel_active
                        _fsp_panel_action = nil
                        point = axlEnterPoint(
                            ?prompts list("Moka skill - Pin Swap: \312\271\323\303\323\322\262\340\303\346\260\345\262\331\327\367\243\254\323\322\274\374 Done \315\313\263\366\241\243"))
                        when(point axlClearSelSet())
                        action = _fsp_panel_action
                        _fsp_panel_action = nil
                        case(action
                            ("SWAP" pin_swap_cmd())
                            ("PINMAP_EXPORT" fsp_pinmap_export_cmd())
                            ("PINMAP_IMPORT" fsp_pinmap_import_cmd())
                        )
                        fsp_ui_refresh()
                    )
                    progn(
                        when(!_fsp_ui_ministatus && form
                            errset(axlFormClose(form) nil)
                        )
                        _fsp_ui_form = nil
                        _fsp_ui_list_items = nil
                        _fsp_ui_ministatus = nil
                        _fsp_panel_action = nil
                        _fsp_panel_active = nil
                        axlClearSelSet()
                        errset(axlSetFindFilter(
                            ?enabled saved_enabled ?onButtons saved_on) nil)
                    )
                )
            else
                _fsp_panel_active = nil
                axlMsgPut("Moka skill - Pin Swap: \316\336\267\250\264\264\275\250\273\273 Pin \277\330\326\306\303\346\260\345\241\243")
            )
        else
            _fsp_panel_active = nil
            axlMsgPut("Moka skill - Pin Swap: \316\336\267\250\264\264\275\250\273\273 Pin \277\330\326\306\303\346\260\345\266\250\322\345\241\243")
        )
        t
    )
)

defun( fsp_ui_close_if_pending ()
    let((form)
        when(_fsp_ui_close_pending
            _fsp_ui_close_pending = nil
            form = _fsp_ui_form
            _fsp_ui_form = nil
            _fsp_ui_list_items = nil
            if(_fsp_panel_active then
                fsp_panel_stop()
            else
                when(form
                    errset(axlFormClose(form) nil)
                )
            )
        )
    )
)

defun( fsp_valid_pin (pin)
    pin &&
    pin->objType == "pin" &&
    pin->parent == _fsp_symbol &&
    !pin->isMech &&
    pin->number
)

defun( fsp_select_component ()
    let((selected symbol)
        symbol = nil
        fsp_ui_set_status("\307\353\324\332\273\255\262\274\326\320\321\241\324\361\322\273\270\366\306\367\274\376\241\243")
        axlClearSelSet()
        axlSetFindFilter(
            ?enabled list("noall" "components" "symbols")
            ?onButtons list("noall" "components" "symbols")
        )
        if(axlSelect(?prompt "Moka skill - Pin Swap: \307\353\321\241\324\361\322\273\270\366\306\367\274\376\243\254\323\322\274\374 Cancel \277\311\315\313\263\366\241\243") && !_fsp_finished then
            selected = axlGetSelSet()
            when(selected
                symbol = fsp_normalize_symbol(car(selected))
            )
        )
        axlClearSelSet()
        symbol
    )
)

defun( fsp_select_pin (prompt_text)
    let((selected pin)
        pin = nil
        axlClearSelSet()
        axlSetFindFilter(
            ?enabled list("noall" "pins")
            ?onButtons list("noall" "pins")
        )
        if(axlSelect(?prompt prompt_text) && !_fsp_finished then
            selected = axlGetSelSet()
            when(selected
                pin = car(selected)
            )
        )
        axlClearSelSet()
        pin
    )
)

defun( fsp_force_swap_pair (pin1 pin2)
    let((net1 net2 result1 result2 ok)
        net1 = fsp_pin_net(pin1)
        net2 = fsp_pin_net(pin2)
        ok = nil

        if(net1 == net2 then
            axlMsgPut(
                sprintf(
                    nil
                    "Moka skill - Pin Swap: %s \272\315 %s \322\321\301\254\275\323\265\275\315\254\322\273\315\370\302\347 %s\243\254\307\353\321\241\324\361\306\344\313\373\265\332\266\376\322\375\275\305\241\243"
                    fsp_pin_label(pin1)
                    fsp_pin_label(pin2)
                    fsp_net_label(net1)
                )
            )
            fsp_ui_set_status("\301\275\270\366\322\375\275\305\322\321\301\254\275\323\265\275\315\254\322\273\315\370\302\347\243\254\307\353\321\241\324\361\306\344\313\373\265\332\266\376\322\375\275\305\241\243")
        else
            if(!axlDBTransactionMark(_fsp_mark) then
                axlMsgPut("Moka skill - Pin Swap: \316\336\267\250\264\264\275\250\263\267\317\372\261\352\274\307\241\243")
                fsp_ui_set_status("\316\336\267\250\264\264\275\250\270\303\322\375\275\305\327\351\265\304\263\267\317\372\261\352\274\307\241\243")
            else
                result1 = errset(axlDBAssignNet(pin1 net2 nil t) nil)
                if(result1 && car(result1) then
                    result2 = errset(axlDBAssignNet(pin2 net1 nil t) nil)
                )

                if(result1 && car(result1) && result2 && car(result2) then
                    _fsp_swap_count = _fsp_swap_count + 1
                    _fsp_session_records = cons(fsp_swap_record(pin1 net1 pin2 net2) _fsp_session_records)
                    ok = t
                    axlMsgPut(
                        sprintf(
                            nil
                            "Moka skill - Pin Swap: %s [%s] <-> %s [%s]\241\243\307\353\321\241\324\361\317\302\322\273\327\351\265\332\322\273\322\375\275\305\243\254\273\362\323\322\274\374 Done/Oops/Cancel\241\243"
                            fsp_pin_label(pin1)
                            fsp_net_label(net1)
                            fsp_pin_label(pin2)
                            fsp_net_label(net2)
                        )
                    )
                    fsp_ui_set_status(
                        sprintf(
                            nil
                            "\322\321\275\273\273\273 %s \272\315 %s\243\254\307\353\321\241\324\361\317\302\322\273\327\351\265\332\322\273\322\375\275\305\273\362\265\343\273\367\241\260\315\352\263\311\241\261\241\243"
                            fsp_pin_label(pin1)
                            fsp_pin_label(pin2)
                        )
                    )
                else
                    axlDBTransactionOops(_fsp_mark)
                    axlMsgPut("Moka skill - Pin Swap: \315\370\302\347\326\330\320\302\267\326\305\344\312\247\260\334\243\254\270\303\322\375\275\305\327\351\322\321\273\330\271\366\241\243")
                    fsp_ui_set_status("\315\370\302\347\326\330\320\302\267\326\305\344\312\247\260\334\243\254\270\303\322\375\275\305\327\351\322\321\273\330\271\366\241\243")
                )
            )
        )
        ok
    )
)

defun( fsp_handle_pin_pick (pin)
    if(!fsp_valid_pin(pin) then
        axlMsgPut("Moka skill - Pin Swap: \307\353\321\241\324\361\265\261\307\260\306\367\274\376\311\317\265\304\267\307\273\372\320\265\322\375\275\305\241\243")
        fsp_ui_set_status("\307\353\321\241\324\361\265\261\307\260\306\367\274\376\311\317\265\304\267\307\273\372\320\265\322\375\275\305\241\243")
    else
        if(!_fsp_first_pin then
            _fsp_first_pin = pin
            errset(axlHighlightObject(_fsp_first_pin t) nil)
            axlMsgPut(
                sprintf(
                    nil
                    "Moka skill - Pin Swap: \265\332\322\273\322\375\275\305 %s [%s]\243\254\307\353\321\241\324\361\265\332\266\376\322\375\275\305\241\243"
                    fsp_pin_label(_fsp_first_pin)
                    fsp_net_label(fsp_pin_net(_fsp_first_pin))
                )
            )
            fsp_ui_set_status(
                sprintf(
                    nil
                    "\265\332\322\273\322\375\275\305 %s [%s]\243\254\307\353\321\241\324\361\265\332\266\376\322\375\275\305\241\243"
                    fsp_pin_label(_fsp_first_pin)
                    fsp_net_label(fsp_pin_net(_fsp_first_pin))
                )
            )
        else
            if(pin == _fsp_first_pin then
                axlMsgPut("Moka skill - Pin Swap: \307\353\321\241\324\361\306\344\313\373\265\332\266\376\322\375\275\305\243\254\273\362\323\322\274\374 Oops \307\345\263\375\265\332\322\273\322\375\275\305\241\243")
                fsp_ui_set_status("\307\353\321\241\324\361\306\344\313\373\265\332\266\376\322\375\275\305\243\254\273\362\312\271\323\303 Oops \307\345\263\375\265\332\322\273\322\375\275\305\241\243")
            else
                when(fsp_force_swap_pair(_fsp_first_pin pin)
                    fsp_clear_first_pin()
                )
            )
        )
    )
)

defun( pin_swap_cmd ()
    let((popup pin prompt_text committed_count)
        _fsp_run_active = t
        _fsp_finished = nil
        _fsp_commit = nil
        _fsp_mark = nil
        _fsp_symbol = nil
        _fsp_first_pin = nil
        _fsp_swap_count = 0
        _fsp_session_records = nil

        fsp_ui_set_status("\307\353\324\332\273\255\262\274\326\320\321\241\324\361\322\273\270\366\306\367\274\376\241\243")

        popup = axlUIPopupDefine(
            nil
            list(
                list("Done" 'fsp_cb_done)
                list("Oops" 'fsp_cb_oops)
                list("Cancel" 'fsp_cb_cancel)
            )
        )
        axlUIPopupSet(popup)

        unwindProtect(
            progn(
                _fsp_symbol = fsp_select_component()
                if(_fsp_symbol && !_fsp_finished then
                    if(
                        axlUIYesNo(
                            sprintf(
                                nil
                                "\312\307\267\361\275\273\273\273\306\367\274\376 %s \265\304\322\375\275\305\243\277\324\255\301\254\275\323\317\337\275\253\261\243\301\364\243\254Pin \265\304 FIXED \327\264\314\254\275\253\261\273\272\366\302\324\241\243"
                                fsp_symbol_refdes(_fsp_symbol)
                            )
                            "Moka skill - \273\273 Pin"
                            'no
                        )
                    then
                        _fsp_mark = axlDBTransactionStart()
                        if(_fsp_mark then
                            fsp_ui_set_status(
                                sprintf(
                                    nil
                                    "\306\367\274\376 %s \322\321\274\244\273\356\243\254\307\353\321\241\324\361\265\332\322\273\322\375\275\305\241\243"
                                    fsp_symbol_refdes(_fsp_symbol)
                                )
                            )
                            while(!_fsp_finished
                                if(_fsp_first_pin then
                                    prompt_text = sprintf(
                                        nil
                                        "\273\273 Pin %s\243\272\307\353\316\252 %s \321\241\324\361\265\332\266\376\322\375\275\305\243\254\323\322\274\374 Oops \277\311\307\345\263\375\241\243"
                                        fsp_symbol_refdes(_fsp_symbol)
                                        fsp_pin_label(_fsp_first_pin)
                                    )
                                else
                                    prompt_text = sprintf(
                                        nil
                                        "\273\273 Pin %s\243\272\307\353\321\241\324\361\265\332\322\273\322\375\275\305\243\254\323\322\274\374\277\311\321\241\324\361 Done/Oops/Cancel\241\243"
                                        fsp_symbol_refdes(_fsp_symbol)
                                    )
                                )
                                pin = fsp_select_pin(prompt_text)
                                when(pin && !_fsp_finished
                                    fsp_handle_pin_pick(pin)
                                )
                            )
                        else
                            axlMsgPut("Moka skill - Pin Swap: \316\336\267\250\306\364\266\257\312\375\276\335\277\342\312\302\316\361\241\243")
                            fsp_ui_set_status("\316\336\267\250\306\364\266\257\312\375\276\335\277\342\312\302\316\361\241\243")
                        )
                    else
                        _fsp_finished = t
                        _fsp_commit = nil
                        fsp_ui_set_status("\316\264\277\252\312\274\273\273 Pin\241\243")
                    )
                )
            )
            progn(
                fsp_clear_first_pin()
                if(_fsp_mark then
                    if(_fsp_commit then
                        if(axlDBTransactionCommit(_fsp_mark) then
                            committed_count = _fsp_swap_count
                            when(_fsp_session_records
                                _fsp_export_records = append(_fsp_session_records _fsp_export_records)
                            )
                            _fsp_session_records = nil
                            axlMsgPut(sprintf(nil "Moka skill - Pin Swap: \322\321\314\341\275\273 %d \327\351\322\375\275\305\275\273\273\273\241\243" _fsp_swap_count))
                            if(committed_count > 0 then
                                fsp_ui_set_status(
                                    sprintf(
                                        nil
                                        "\322\321\314\341\275\273 %d \327\351\322\375\275\305\275\273\273\273\243\254\277\311\322\324\265\274\263\366\310\325\326\276\241\243"
                                        committed_count
                                    )
                                )
                            else
                                fsp_ui_set_status("\322\321\315\352\263\311\243\254\316\264\275\370\320\320\322\375\275\305\275\273\273\273\241\243")
                            )
                        else
                            axlMsgPut("Moka skill - Pin Swap: \312\302\316\361\314\341\275\273\312\247\260\334\241\243")
                            _fsp_session_records = nil
                            fsp_ui_set_status("\312\302\316\361\314\341\275\273\312\247\260\334\243\254\316\264\317\362\265\274\263\366\310\325\326\276\314\355\274\323\320\305\317\242\241\243")
                        )
                    else
                        axlDBTransactionRollback(_fsp_mark)
                        _fsp_session_records = nil
                        axlMsgPut("Moka skill - Pin Swap: \262\331\327\367\322\321\310\241\317\373\243\254\313\371\323\320\270\374\270\304\322\321\273\330\271\366\241\243")
                        fsp_ui_set_status("\322\321\310\241\317\373\243\254\265\261\307\260\262\331\327\367\326\320\265\304\313\371\323\320\270\374\270\304\276\371\322\321\273\330\271\366\241\243")
                    )
                else
                    _fsp_session_records = nil
                    if(_fsp_commit then
                        fsp_ui_set_status("\303\273\323\320\277\311\315\352\263\311\265\304\273\356\266\257\312\302\316\361\241\243")
                    else
                        when(equal(_fsp_ui_status "\325\375\324\332\310\241\317\373\262\242\273\330\271\366\265\261\307\260\273\273 Pin \262\331\327\367...")
                            fsp_ui_set_status("\322\321\310\241\317\373\243\254\316\264\275\370\320\320\310\316\272\316\270\374\270\304\241\243")
                        )
                    )
                )
                axlUIPopupSet(nil)
                axlClearSelSet()
                _fsp_mark = nil
                _fsp_symbol = nil
                _fsp_first_pin = nil
                _fsp_run_active = nil
                fsp_ui_refresh()
                fsp_ui_close_if_pending()
            )
        )
    )
)
