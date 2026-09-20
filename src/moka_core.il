; ==============================================================================
; Script Name: moka_core.il
; Description: Moka skill v1.0 (routing helpers, stackup, impedance and analysis tools)
; Modifications: Version 1.0 - Add Anti Etch layer visibility settings
; ==============================================================================

defvar(moka_install_dir axlGetVariable("MOKA_INSTALL_DIR") || "D:/Moka_Skill")

; Moka Globals
defvar(moka_layer_table nil)
defvar(moka_display_mode "SINGLE") 
defvar(moka_c1_class "")
defvar(moka_c1_sub "")
defvar(moka_c2_class "")
defvar(moka_c2_sub "")

; Trace Analyzer Globals
defvar(ta_dbTable nil)
defvar(ta_lastKeys nil)
defvar(ta_lastListItems nil)
defvar(ta_mainFormHandle nil)
defvar(ta_paletteFormHandle nil)
defvar(moka_mainFormHandle nil)
defvar(moka_refdesFormHandle nil)
defvar(moka_refdes_active nil)
defvar(moka_refdes_find_filter_saved nil)
defvar(moka_refdes_find_enabled_saved nil)
defvar(moka_refdes_find_on_saved nil)
defvar(moka_refdes_view_flipped nil)
defvar(moka_refdes_display_mode "TOP")

; Commands Registration
axlCmdRegister("moka_prev" 'moka_cmd_prev ?cmdType "general")
axlCmdRegister("moka_next" 'moka_cmd_next ?cmdType "general")
axlCmdRegister("moka_all"  'moka_toggle_single_all ?cmdType "general")
axlCmdRegister("moka_via"  'moka_cmd_via_toggle ?cmdType "general") 
axlCmdRegister("moka_mode" 'moka_cmd_mode_toggle ?cmdType "general")
axlCmdRegister("moka_width" 'moka_cmd_change_width ?cmdType "general") 
axlCmdRegister("mokaskill" 'moka_cmd_ui)
axlCmdRegister(
    "moka_refdes"
    'moka_refdes_ui_open
    ?cmdType "interactive"
    ?doneCmd 'moka_refdes_done
    ?cancelCmd 'moka_refdes_cancel)
axlCmdRegister("moka_info" 'moka_cmd_get_status ?cmdType "general")
axlCmdRegister("moka_ta" 'Run_TraceAnalyzerTool) ; Trace Analyzer Command

defun( moka_safe_str (v)
    if(stringp(v) then v else "")
)

defun( moka_custom_layer_name (grp sub)
    if(stringp(grp) && strlen(grp) > 0 && stringp(sub) && strlen(sub) > 0 then
        strcat(upperCase(grp) "/" upperCase(sub))
    else
        ""
    )
)

defun( moka_layer_exists_safe (layer_name)
    let((result)
        result = nil
        when(stringp(layer_name) && strlen(layer_name) > 0
            result = errset(axlIsLayer(layer_name) nil)
        )
        result && car(result)
    )
)

defun( moka_class_exists_safe (grp)
    let((result param)
        result = nil
        when(stringp(grp) && strlen(grp) > 0
            result = errset(axlGetParam(sprintf(nil "paramLayerGroup:%s" grp)) nil)
            param = if(result then car(result) else nil)
        )
        param && param->groupMembers
    )
)

defun( moka_set_custom_class_sub (slot grp sub)
    let((class_name sub_name full_name)
        class_name = if(stringp(grp) then upperCase(grp) else "")
        sub_name = if(stringp(sub) then upperCase(sub) else "")
        unless(moka_class_exists_safe(class_name)
            class_name = ""
            sub_name = ""
        )
        full_name = moka_custom_layer_name(class_name sub_name)
        unless(strlen(full_name) == 0 || moka_layer_exists_safe(full_name)
            sub_name = ""
            full_name = ""
        )
        if(slot == 1 then
            moka_c1_class = class_name
            moka_c1_sub = sub_name
        else
            moka_c2_class = class_name
            moka_c2_sub = sub_name
        )
        full_name
    )
)

defun( moka_set_custom_layer (slot layer_name)
    let((parts grp sub)
        grp = ""
        sub = ""
        when(stringp(layer_name) && strlen(layer_name) > 0
            parts = parseString(layer_name "/")
            when(length(parts) >= 2
                grp = nth(0 parts)
                sub = nth(1 parts)
            )
        )
        moka_set_custom_class_sub(slot grp sub)
    )
)

defun( moka_subclass_popup (grp)
    let((group_param popup full_name color_idx valid_layer)
        popup = list(list("(None)" "" nil))
        when(moka_class_exists_safe(grp)
            group_param = axlGetParam(sprintf(nil "paramLayerGroup:%s" grp))
            foreach(sub group_param->groupMembers
                full_name = strcat(upperCase(grp) "/" upperCase(sub))
                valid_layer = moka_layer_exists_safe(full_name)
                when(valid_layer && length(popup) < 1000
                    color_idx = moka_get_color_safe(grp sub)
                    popup = append(popup list(list(upperCase(sub) upperCase(sub) color_idx)))
                )
            )
        )
        popup
    )
)

defun( moka_class_popup ()
    let((root classes popup subclasses)
        popup = list(list("(None)" ""))
        root = axlGetParam("paramLayerGroup")
        classes = if(root then root->groupMembers else nil)
        foreach(grp classes
            subclasses = moka_subclass_popup(grp)
            when(length(subclasses) > 1
                popup = append(popup list(list(upperCase(grp) upperCase(grp))))
            )
        )
        popup
    )
)

; ==============================================================================
; 安全取色函数
; ==============================================================================
defun( moka_get_color_safe (grp sub)
    let((c_idx p)
        errset(p = axlGetParam(sprintf(nil "paramLayerGroup:%s/paramLayer:%s" grp sub)) nil)
        c_idx = if(p && p->color then p->color else nil)
        
        if(!c_idx || !numberp(c_idx) then
            errset(p = axlGetParam(sprintf(nil "paramLayerGroup:%s/paramLayerSubclass:%s" grp sub)) nil)
            c_idx = if(p && p->color then p->color else nil)
        )
        
        if(!c_idx || !numberp(c_idx) then
            errset(c_idx = axlGetSubclassColor(grp sub) nil)
        )
        
        if(!c_idx || !numberp(c_idx) then c_idx = 1)
        if(c_idx > 192 then c_idx = mod(c_idx 192))
        
        c_idx
    )
)

defun( moka_load_config_ini ()
    let((file port line idx key val layer_data temp_table ln rowData state_count)
        file = strcat(moka_install_dir "/moka_config.ini")
        if(isFile(file) then
            temp_table = nil
            port = infile(file)
            while(gets(line port)
                line = buildString(parseString(line "\n\r") "")
                idx = nindex(line "=")
                if(idx then
                    key = substring(line 1 idx-1)
                    val = substring(line idx+1)
                    case(key
                        ("c1_class" moka_c1_class = val)
                        ("c1_sub" moka_c1_sub = val)
                        ("c2_class" moka_c2_class = val)
                        ("c2_sub" moka_c2_sub = val)
                        ("LAYER"
                            layer_data = parseString(val "|")
                            if(length(layer_data) >= 18 then
                                ln = nth(0 layer_data)
                                rowData = nil
                                state_count = if(length(layer_data) >= 19 then 18 else 17)
                                for(k 1 state_count
                                    rowData = cons(if(nth(state_count+1-k layer_data) == "1" t nil) rowData)
                                )
                                rowData = cons(ln rowData)
                                ; v1.0 migration: old rows did not contain Anti Etch.
                                when(state_count == 17
                                    rowData = append(rowData list(nil))
                                )
                                temp_table = cons(rowData temp_table)
                            )
                        )
                    )
                )
            )
            close(port)
            if(temp_table then moka_layer_table = reverse(temp_table))
        )
    )
)

defun( moka_save_config_ini ()
    let((port file)
        file = strcat(moka_install_dir "/moka_config.ini")
        port = outfile(file)
        if(port then
            fprintf(port "[CUSTOM_CLASSES]\n")
            fprintf(port "c1_class=%s\n" moka_safe_str(moka_c1_class))
            fprintf(port "c1_sub=%s\n" moka_safe_str(moka_c1_sub))
            fprintf(port "c2_class=%s\n" moka_safe_str(moka_c2_class))
            fprintf(port "c2_sub=%s\n" moka_safe_str(moka_c2_sub))
            fprintf(port "\n[LAYER_SETTINGS]\n")
            
            foreach(row moka_layer_table
                let((ln str)
                    ln = nth(0 row)
                    str = sprintf(nil "LAYER=%s" ln)
                    for(k 1 18
                        str = strcat(str "|" if(nth(k row) "1" "0"))
                    )
                    fprintf(port "%s\n" str)
                )
            )
            close(port)
            ; 配置已成功应用并保存！
            axlMsgPut("Moka skill: \305\344\326\303\322\321\263\311\271\246\323\246\323\303\262\242\261\243\264\346\243\241")
        else
            ; 保存配置文件失败:
            axlMsgPut("Moka skill: \261\243\264\346\305\344\326\303\316\304\274\376\312\247\260\334: %s" file)
        )
    )
)

defun( moka_cmd_via_toggle ()
    if(moka_try_cycle_route_via() then
    ; 已切换至下一个过孔。
        axlMsgPut("Moka skill: \322\321\307\320\273\273\326\301\317\202\322\273\270\366\271\375\277\327\241\243")
    )
)

defun( moka_cmd_mode_toggle ()
    if(moka_try_cycle_move_point() then
        axlMsgPut("Moka skill: Move Point mode cycled.")
    else
        if(moka_try_cycle_connect_bubble() then
            axlMsgPut("Moka skill: Connect Bubble mode cycled.")
        else
            axlMsgPut("Moka skill: Mode toggle is unavailable in the current command.")
        )
    )
)

defun( moka_try_form_next_field (field_name)
    let((ok level prev_level result)
        ok = t
        prev_level = axlMsgTest()
        axlMsgClear()

        result = errset(axlShell("setwindow form.mini") nil)
        if(!result then ok = nil)

        if(ok then
            result = errset(axlShell(sprintf(nil "form_next mini %s" field_name)) nil)
            if(!result then ok = nil)
        )

        errset(axlShell("setwindow pcb") nil)

        level = axlMsgTest()
        if(numberp(level) && level >= 3 then
            ok = nil
        )

        axlMsgClear()
        if(numberp(prev_level) && prev_level > 0 then
            axlMsgSet(prev_level)
        )

        ok
    )
)

defun( moka_cmd_change_width ()
    let((new_width)
        ; 请输入新的线宽:
        new_width = axlUIPrompt("\307\353\312\344\310\353\320\302\265\304\317\337\277\355:")
        if(stringp(new_width) && strlen(new_width) > 0 then
            if(moka_try_set_route_width(new_width) then
            ; 当前走线宽度已更新为 -> 
                axlMsgPut("Moka skill: \265\261\307\260\327\337\317\337\277\355\266\310\322\321\270\374\320\302\316\252 -> %s" new_width)
            )
        )
    )
)

defun( moka_try_set_route_width (new_width)
    let((ok fields result)
        ok = t
        fields = list("acon_line_width" "acon_act_width")
        result = errset(axlShell("setwindow pcb") nil)
        if(!result then ok = nil)
        result = errset(axlShell("setwindow form.mini") nil)
        if(!result then ok = nil)
        if(ok then
            foreach(ff fields
                result = errset(axlShell(sprintf(nil "FORM mini %s %s" ff new_width)) nil)
                if(!result then ok = nil)
            )
        )
        errset(axlShell("setwindow pcb") nil)
        ok
    )
)

defun( moka_try_cycle_route_via ()
    errset(axlShell("setwindow form.mini; form_next mini padstack_list; setwindow pcb") nil)
)

defun( moka_try_cycle_move_point ()
    moka_try_form_next_field("rotate_point")
)

defun( moka_try_cycle_connect_bubble ()
    moka_try_form_next_field("bubble_space")
)

defun( moka_default_layer_row (layer)
    let((mst msb slkt slkb reft refb bndt bndb)
        mst=nil msb=nil slkt=nil slkb=nil reft=nil refb=nil bndt=nil bndb=nil
        if(equal(upperCase(layer) "TOP") then mst=t slkt=t reft=t bndt=t)
        if(equal(upperCase(layer) "BOTTOM") then msb=t slkb=t refb=t bndb=t)
        list(layer t t t t mst msb slkt slkb reft refb bndt bndb nil nil nil nil nil nil)
    )
)

defun( moka_find_saved_layer_row (table layer)
    let((found)
        found = nil
        foreach(row table
            when(!found && listp(row) && length(row) >= 19 &&
                 equal(upperCase(moka_safe_str(car(row))) upperCase(layer))
                found = row
            )
        )
        found
    )
)

defun( moka_reconcile_layer_table ()
    let((layers old_table new_table saved_row)
        layers = axlGetParam("paramLayerGroup:ETCH")->groupMembers
        old_table = moka_layer_table
        new_table = nil
        foreach(layer layers
            saved_row = moka_find_saved_layer_row(old_table layer)
            if(saved_row then
                new_table = cons(cons(layer cdr(saved_row)) new_table)
            else
                new_table = cons(moka_default_layer_row(layer) new_table)
            )
        )
        moka_layer_table = reverse(new_table)
    )
)

defun( moka_init_table ()
    let((layers)
        layers = axlGetParam("paramLayerGroup:ETCH")->groupMembers
        moka_layer_table = nil
        foreach(layer layers
            moka_layer_table = cons(moka_default_layer_row(layer) moka_layer_table)
        )
        moka_layer_table = reverse(moka_layer_table)
    )
)

defun( moka_sync_table ()
    unless(moka_layer_table moka_load_config_ini())
    when(moka_layer_table && length(car(moka_layer_table)) == 18
        let((migrated_table)
            migrated_table = nil
            foreach(row moka_layer_table
                migrated_table = cons(append(row list(nil)) migrated_table)
            )
            moka_layer_table = reverse(migrated_table)
        )
    )
    if(moka_layer_table && length(car(moka_layer_table)) < 19 then moka_layer_table = nil)
    unless(moka_layer_table moka_init_table())
    moka_reconcile_layer_table()
)

defun( moka_cycle_layer (direction)
    if(moka_refdes_active then
        moka_refdes_cycle_side(direction)
    else
        progn(
            moka_sync_table()
            let((layers active_layer curr_idx target_idx found layers_num count)
                layers = axlGetParam("paramLayerGroup:ETCH")->groupMembers
                layers_num = length(layers)
                active_layer = nthelem(2 parseString(axlGetActiveLayer() "/"))
                curr_idx = 0
                for(i 0 layers_num-1
                    if(equal(nth(i layers) active_layer) then curr_idx = i)
                )
                target_idx = curr_idx
                found = nil
                count = 0
                while(count < layers_num && !found
                    if(equal(direction "next") then
                        target_idx = target_idx + 1
                        if(target_idx >= layers_num then target_idx = 0)
                    else
                        target_idx = target_idx - 1
                        if(target_idx < 0 then target_idx = layers_num - 1)
                    )
                    if(nth(1 nth(target_idx moka_layer_table)) then found = t)
                    count++
                )
                if(found then moka_apply_view(nth(target_idx moka_layer_table))
                ; No other enabled layer was found.
                else axlMsgPut("Moka skill: \316\264\325\322\265\275\306\344\313\373\322\321\306\364\323\303\265\304\262\343\241\243")
                )
            )
        )
    )
)

defun( moka_cmd_prev () moka_cycle_layer("prev"))
defun( moka_cmd_next () moka_cycle_layer("next"))

defun( moka_toggle_single_all ()
    moka_sync_table()
    if(equal(moka_display_mode "SINGLE") then
        moka_display_mode = "ALL"
        let((count saved_layer)
            saved_layer = axlGetActiveLayer()
            axlVisibleDesign(nil)
            
            count = 0
            foreach(cfg moka_layer_table
                if(nth(1 cfg) then 
                    let((ln pin via drc mst msb slkt slkb reft refb bndt bndb rki rko c1 c2 bound anti c1_layer c2_layer)
                        ln = nth(0 cfg) pin = nth(2 cfg) via = nth(3 cfg) drc = nth(4 cfg)
                        mst = nth(5 cfg) msb = nth(6 cfg) slkt = nth(7 cfg) slkb = nth(8 cfg)
                        reft = nth(9 cfg) refb = nth(10 cfg) bndt = nth(11 cfg) bndb = nth(12 cfg)
                        rki = nth(13 cfg) rko = nth(14 cfg) c1 = nth(15 cfg) c2 = nth(16 cfg)
                        bound = nth(17 cfg) anti = nth(18 cfg)
                        
                        axlVisibleLayer(strcat("ETCH/" ln) t)
                        if(pin   then axlVisibleLayer(strcat("PIN/" ln) t))
                        if(via   then axlVisibleLayer(strcat("VIA CLASS/" ln) t))
                        if(drc   then axlVisibleLayer(strcat("DRC ERROR CLASS/" ln) t))
                        
                        if(mst  then 
                            axlVisibleLayer("BOARD GEOMETRY/SOLDERMASK_TOP" t)
                            axlVisibleLayer("PACKAGE GEOMETRY/SOLDERMASK_TOP" t)
                            axlVisibleLayer("PIN/SOLDERMASK_TOP" t)
                            axlVisibleLayer("VIA CLASS/SOLDERMASK_TOP" t)
                        )
                        if(slkt then 
                            axlVisibleLayer("BOARD GEOMETRY/SILKSCREEN_TOP" t)
                            axlVisibleLayer("PACKAGE GEOMETRY/SILKSCREEN_TOP" t)
                        )
                        if(reft then axlVisibleLayer("REF DES/SILKSCREEN_TOP" t))
                        if(bndt then axlVisibleLayer("PACKAGE GEOMETRY/PLACE_BOUND_TOP" t))
                        
                        if(msb  then 
                            axlVisibleLayer("BOARD GEOMETRY/SOLDERMASK_BOTTOM" t)
                            axlVisibleLayer("PACKAGE GEOMETRY/SOLDERMASK_BOTTOM" t)
                            axlVisibleLayer("PIN/SOLDERMASK_BOTTOM" t)
                            axlVisibleLayer("VIA CLASS/SOLDERMASK_BOTTOM" t)
                        )
                        if(slkb then 
                            axlVisibleLayer("BOARD GEOMETRY/SILKSCREEN_BOTTOM" t)
                            axlVisibleLayer("PACKAGE GEOMETRY/SILKSCREEN_BOTTOM" t)
                        )
                        if(refb then axlVisibleLayer("REF DES/SILKSCREEN_BOTTOM" t))
                        if(bndb then axlVisibleLayer("PACKAGE GEOMETRY/PLACE_BOUND_BOTTOM" t))
                        
                        if(rki then
                            if(axlIsLayer("ROUTE KEEPIN/ALL") then axlVisibleLayer("ROUTE KEEPIN/ALL" t))
                            if(axlIsLayer(strcat("ROUTE KEEPIN/" ln)) then axlVisibleLayer(strcat("ROUTE KEEPIN/" ln) t))
                        )
                        if(rko then
                            if(axlIsLayer("ROUTE KEEPOUT/ALL") then axlVisibleLayer("ROUTE KEEPOUT/ALL" t))
                            if(axlIsLayer(strcat("ROUTE KEEPOUT/" ln)) then axlVisibleLayer(strcat("ROUTE KEEPOUT/" ln) t))
                        )
                        
                        if(bound then
                            if(axlIsLayer(strcat("BOUNDARY/" ln)) then axlVisibleLayer(strcat("BOUNDARY/" ln) t))
                        )
                        if(anti then
                            if(axlIsLayer(strcat("ANTI ETCH/" ln)) then axlVisibleLayer(strcat("ANTI ETCH/" ln) t))
                        )
                        
                        if(c1 && stringp(moka_c1_class) && strlen(moka_c1_class)>0 && stringp(moka_c1_sub) && strlen(moka_c1_sub)>0 then
                            c1_layer = strcat(upperCase(moka_c1_class) "/" upperCase(moka_c1_sub))
                            if(axlIsLayer(c1_layer) then axlVisibleLayer(c1_layer t))
                        )
                        if(c2 && stringp(moka_c2_class) && strlen(moka_c2_class)>0 && stringp(moka_c2_sub) && strlen(moka_c2_sub)>0 then
                            c2_layer = strcat(upperCase(moka_c2_class) "/" upperCase(moka_c2_sub))
                            if(axlIsLayer(c2_layer) then axlVisibleLayer(c2_layer t))
                        )
                        count++
                    )
                )
            )
            axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
            if(axlIsLayer("BOARD GEOMETRY/DESIGN_OUTLINE") then axlVisibleLayer("BOARD GEOMETRY/DESIGN_OUTLINE" t))
            
            if(saved_layer && axlIsLayer(saved_layer) then axlSetActiveLayer(saved_layer))
            
            axlVisibleUpdate(t)
            ; 多层显示切换 (当前显示 %d 层)
            axlMsgPut("Moka skill: \266\340\262\343\317\324\312\276\307\320\273\273 (\265\261\307\260\317\324\312\276 %d \262\343)" count)
        )
    else
        let((active_layer curr_cfg)
            active_layer = nthelem(2 parseString(axlGetActiveLayer() "/"))
            foreach(cfg moka_layer_table if(equal(nth(0 cfg) active_layer) then curr_cfg = cfg))
            ; 无法识别当前活动层。
            if(curr_cfg then moka_apply_view(curr_cfg) else axlMsgPut("Moka skill: \316\336\267\250\312\266\261\360\265\261\307\260\273\356\266\257\262\343\241\243"))
        )
    )
)

defun( moka_apply_view (cfg)
    moka_display_mode = "SINGLE" 
    let((ln pin via drc mst msb slkt slkb reft refb bndt bndb rki rko c1 c2 bound anti c1_layer c2_layer)
        ln = nth(0 cfg) pin = nth(2 cfg) via = nth(3 cfg) drc = nth(4 cfg)
        mst = nth(5 cfg) msb = nth(6 cfg) slkt = nth(7 cfg) slkb = nth(8 cfg)
        reft = nth(9 cfg) refb = nth(10 cfg) bndt = nth(11 cfg) bndb = nth(12 cfg)
        rki = nth(13 cfg) rko = nth(14 cfg) c1 = nth(15 cfg) c2 = nth(16 cfg)
        bound = nth(17 cfg) anti = nth(18 cfg)
        
        axlVisibleDesign(nil)
        axlVisibleLayer(strcat("ETCH/" ln) t)
        
        if(pin   then axlVisibleLayer(strcat("PIN/" ln) t))
        if(via   then axlVisibleLayer(strcat("VIA CLASS/" ln) t))
        if(drc   then axlVisibleLayer(strcat("DRC ERROR CLASS/" ln) t))
        
        if(mst  then 
            axlVisibleLayer("BOARD GEOMETRY/SOLDERMASK_TOP" t)
            axlVisibleLayer("PACKAGE GEOMETRY/SOLDERMASK_TOP" t)
            axlVisibleLayer("PIN/SOLDERMASK_TOP" t)
            axlVisibleLayer("VIA CLASS/SOLDERMASK_TOP" t)
        )
        if(slkt then 
            axlVisibleLayer("BOARD GEOMETRY/SILKSCREEN_TOP" t)
            axlVisibleLayer("PACKAGE GEOMETRY/SILKSCREEN_TOP" t)
        )
        if(reft then axlVisibleLayer("REF DES/SILKSCREEN_TOP" t))
        if(bndt then axlVisibleLayer("PACKAGE GEOMETRY/PLACE_BOUND_TOP" t))
        
        if(msb  then 
            axlVisibleLayer("BOARD GEOMETRY/SOLDERMASK_BOTTOM" t)
            axlVisibleLayer("PACKAGE GEOMETRY/SOLDERMASK_BOTTOM" t)
            axlVisibleLayer("PIN/SOLDERMASK_BOTTOM" t)
            axlVisibleLayer("VIA CLASS/SOLDERMASK_BOTTOM" t)
        )
        if(slkb then 
            axlVisibleLayer("BOARD GEOMETRY/SILKSCREEN_BOTTOM" t)
            axlVisibleLayer("PACKAGE GEOMETRY/SILKSCREEN_BOTTOM" t)
        )
        if(refb then axlVisibleLayer("REF DES/SILKSCREEN_BOTTOM" t))
        if(bndb then axlVisibleLayer("PACKAGE GEOMETRY/PLACE_BOUND_BOTTOM" t))
        
        if(rki then
            if(axlIsLayer("ROUTE KEEPIN/ALL") then axlVisibleLayer("ROUTE KEEPIN/ALL" t))
            if(axlIsLayer(strcat("ROUTE KEEPIN/" ln)) then axlVisibleLayer(strcat("ROUTE KEEPIN/" ln) t))
        )
        if(rko then
            if(axlIsLayer("ROUTE KEEPOUT/ALL") then axlVisibleLayer("ROUTE KEEPOUT/ALL" t))
            if(axlIsLayer(strcat("ROUTE KEEPOUT/" ln)) then axlVisibleLayer(strcat("ROUTE KEEPOUT/" ln) t))
        )
        
        if(bound then
            if(axlIsLayer(strcat("BOUNDARY/" ln)) then axlVisibleLayer(strcat("BOUNDARY/" ln) t))
        )
        if(anti then
            if(axlIsLayer(strcat("ANTI ETCH/" ln)) then axlVisibleLayer(strcat("ANTI ETCH/" ln) t))
        )
        
        if(c1 && stringp(moka_c1_class) && strlen(moka_c1_class)>0 && stringp(moka_c1_sub) && strlen(moka_c1_sub)>0 then
            c1_layer = strcat(upperCase(moka_c1_class) "/" upperCase(moka_c1_sub))
            if(axlIsLayer(c1_layer) then axlVisibleLayer(c1_layer t))
        )
        if(c2 && stringp(moka_c2_class) && strlen(moka_c2_class)>0 && stringp(moka_c2_sub) && strlen(moka_c2_sub)>0 then
            c2_layer = strcat(upperCase(moka_c2_class) "/" upperCase(moka_c2_sub))
            if(axlIsLayer(c2_layer) then axlVisibleLayer(c2_layer t))
        )
        
        axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
        if(axlIsLayer("BOARD GEOMETRY/DESIGN_OUTLINE") then axlVisibleLayer("BOARD GEOMETRY/DESIGN_OUTLINE" t))
        
        axlSetActiveLayer(strcat("ETCH/" ln))
        axlVisibleUpdate(t)
        ; 单层显示 ->
        axlMsgPut("Moka skill: \265\245\262\343\317\324\312\276 -> %s" ln)
    )
)

defun( moka_create_form_file ()
    let((port file layers row y form_h fileName temp_layers dirs time_str)
        time_str = buildString(parseString(getCurrentTime() " :") "")
        fileName = sprintf(nil "mokaform_%s.form" time_str)
        
        dirs = list(axlGetVariable("TEMP") axlGetVariable("TMP") axlGetVariable("HOME") getWorkingDir())
        port = nil
        file = ""
        
        foreach(dir dirs
            if(stringp(dir) && strlen(dir)>0 && port == nil then
                file = buildString(parseString(strcat(dir "/" fileName) "\\") "/")
                port = outfile(file)
            )
        )
        
        if(port then
            temp_layers = errset(axlGetParam("paramLayerGroup:ETCH")->groupMembers)
            if(temp_layers && car(temp_layers) then
                layers = car(temp_layers)
                form_h = length(layers) * 2 + 20
            else
                form_h = 30
            )
            if(form_h < 30 then form_h = 30)
            
            fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\n")
            fprintf(port "FORM\nFIXED\nPORT 115 %d\nHEADER \"Moka skill v1.0 - \262\343\311\350\326\303\"\n" form_h)
            fprintf(port "POPUP <C1CLASSPOP> \"(None)\" \"\".\n")
            fprintf(port "POPUP <C1SUBPOP> \"(None)\" \"\".\n")
            fprintf(port "POPUP <C2CLASSPOP> \"(None)\" \"\".\n")
            fprintf(port "POPUP <C2SUBPOP> \"(None)\" \"\".\n")
            fprintf(port "TILE\n")
            
            fprintf(port "TEXT \"En\"\nTLOC 2 2\nENDTEXT\n")
            fprintf(port "TEXT \"\262\343\"\nTLOC 6 2\nENDTEXT\n")
            fprintf(port "TEXT \"Pin\"\nTLOC 18 2\nENDTEXT\n")
            fprintf(port "TEXT \"Via\"\nTLOC 23 2\nENDTEXT\n")
            fprintf(port "TEXT \"DRC\"\nTLOC 28 2\nENDTEXT\n")
            fprintf(port "TEXT \"MsT\"\nTLOC 33 2\nENDTEXT\n")
            fprintf(port "TEXT \"MsB\"\nTLOC 38 2\nENDTEXT\n")
            fprintf(port "TEXT \"SlkT\"\nTLOC 43 2\nENDTEXT\n")
            fprintf(port "TEXT \"SlkB\"\nTLOC 48 2\nENDTEXT\n")
            fprintf(port "TEXT \"RefT\"\nTLOC 53 2\nENDTEXT\n")
            fprintf(port "TEXT \"RefB\"\nTLOC 58 2\nENDTEXT\n")
            fprintf(port "TEXT \"BndT\"\nTLOC 63 2\nENDTEXT\n")
            fprintf(port "TEXT \"BndB\"\nTLOC 68 2\nENDTEXT\n")
            fprintf(port "TEXT \"RKI\"\nTLOC 73 2\nENDTEXT\n")
            fprintf(port "TEXT \"RKO\"\nTLOC 78 2\nENDTEXT\n")
            fprintf(port "TEXT \"C1\"\nTLOC 83 2\nENDTEXT\n")
            fprintf(port "TEXT \"C2\"\nTLOC 88 2\nENDTEXT\n")
            fprintf(port "TEXT \"Bound\"\nTLOC 93 2\nENDTEXT\n")
            fprintf(port "TEXT \"Anti Etch\"\nTLOC 99 2\nENDTEXT\n")
            
            y = 5
            for(i 0 length(moka_layer_table)-1
                row = nth(i moka_layer_table)
                fprintf(port "FIELD en_%d\nFLOC 2 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "TEXT \"%s\"\nTLOC 6 %d\nENDTEXT\n" nth(0 row) y)
                fprintf(port "FIELD pin_%d\nFLOC 18 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD via_%d\nFLOC 23 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD drc_%d\nFLOC 28 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD mst_%d\nFLOC 33 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD msb_%d\nFLOC 38 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD slkt_%d\nFLOC 43 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD slkb_%d\nFLOC 48 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD reft_%d\nFLOC 53 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD refb_%d\nFLOC 58 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD bndt_%d\nFLOC 63 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD bndb_%d\nFLOC 68 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD rki_%d\nFLOC 73 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD rko_%d\nFLOC 78 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD c1_%d\nFLOC 83 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD c2_%d\nFLOC 88 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD bound_%d\nFLOC 93 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                fprintf(port "FIELD anti_%d\nFLOC 100 %d\nCOLOR 2 1\nENDFIELD\n" i y)
                y = y + 2
            )
            
            fprintf(port "TEXT \"---ALL---\"\nTLOC 6 %d\nENDTEXT\n" y)
            fprintf(port "FIELD all_en\nFLOC 2 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_pin\nFLOC 18 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_via\nFLOC 23 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_drc\nFLOC 28 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_mst\nFLOC 33 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_msb\nFLOC 38 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_slkt\nFLOC 43 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_slkb\nFLOC 48 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_reft\nFLOC 53 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_refb\nFLOC 58 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_bndt\nFLOC 63 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_bndb\nFLOC 68 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_rki\nFLOC 73 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_rko\nFLOC 78 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_c1\nFLOC 83 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_c2\nFLOC 88 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_bound\nFLOC 93 %d\nCOLOR 2 1\nENDFIELD\n" y)
            fprintf(port "FIELD all_anti\nFLOC 100 %d\nCOLOR 2 1\nENDFIELD\n" y)
            
            y = y + 3
            fprintf(port "TEXT \"C1:\"\nTLOC 2 %d\nENDTEXT\n" y)
            fprintf(port "TEXT \"Class\"\nTLOC 8 %d\nENDTEXT\n" y)
            fprintf(port "FIELD c1_class\nFLOC 15 %d\nENUMSET 20\nOPTIONS prettyprint\nPOP \"C1CLASSPOP\"\nENDFIELD\n" y)
            fprintf(port "TEXT \"Subclass\"\nTLOC 38 %d\nENDTEXT\n" y)
            fprintf(port "FIELD c1_sub\nFLOC 49 %d\nENUMSET 20\nOPTIONS prettyprint ownerdrawn\nPOP \"C1SUBPOP\"\nENDFIELD\n" y)
            
            fprintf(port "TEXT \"C2:\"\nTLOC 2 %d\nENDTEXT\n" y+2)
            fprintf(port "TEXT \"Class\"\nTLOC 8 %d\nENDTEXT\n" y+2)
            fprintf(port "FIELD c2_class\nFLOC 15 %d\nENUMSET 20\nOPTIONS prettyprint\nPOP \"C2CLASSPOP\"\nENDFIELD\n" y+2)
            fprintf(port "TEXT \"Subclass\"\nTLOC 38 %d\nENDTEXT\n" y+2)
            fprintf(port "FIELD c2_sub\nFLOC 49 %d\nENUMSET 20\nOPTIONS prettyprint ownerdrawn\nPOP \"C2SUBPOP\"\nENDFIELD\n" y+2)
            
            y = y + 5
            fprintf(port "FIELD btn_apply\nFLOC 2 %d\nMENUBUTTON \"\323\246\323\303\305\344\326\303\" 15 3\nENDFIELD\n" y)
            fprintf(port "FIELD btn_close\nFLOC 20 %d\nMENUBUTTON \"\271\330\261\325\" 10 3\nENDFIELD\n" y)
            fprintf(port "FIELD btn_ta\nFLOC 35 %d\nMENUBUTTON \"\327\337\317\337\267\326\316\366\" 15 3\nENDFIELD\n" y)
            fprintf(port "FIELD btn_pin_swap\nFLOC 52 %d\nMENUBUTTON \"\273\273 Pin\" 12 3\nENDFIELD\n" y)
            fprintf(port "FIELD btn_dp_antipad\nFLOC 66 %d\nMENUBUTTON \"Anti-Pad\" 16 3\nENDFIELD\n" y)
            fprintf(port "FIELD btn_refdes\nFLOC 84 %d\nMENUBUTTON \"\316\273\272\305\271\244\276\337\" 14 3\nENDFIELD\n" y)
            fprintf(port "ENDTILE\nENDFORM\n")
            close(port)
            
            file
        else
            nil
        )
    )
)

defun( moka_update_cell_color (form field_prefix i layer state)
    let((color_idx group sub field_name is_checked)
        field_name = sprintf(nil "%s_%d" field_prefix i)
        
        is_checked = if(state == "1" || state == t then t else nil)
        
        cond(
            (equal(field_prefix "en")   group = "ETCH"              sub = layer)
            (equal(field_prefix "pin")  group = "PIN"               sub = layer)
            (equal(field_prefix "via")  group = "VIA CLASS"         sub = layer)
            (equal(field_prefix "drc")  group = "DRC ERROR CLASS"   sub = layer)
            (equal(field_prefix "mst")  group = "BOARD GEOMETRY"    sub = "SOLDERMASK_TOP")
            (equal(field_prefix "msb")  group = "BOARD GEOMETRY"    sub = "SOLDERMASK_BOTTOM")
            (equal(field_prefix "slkt") group = "BOARD GEOMETRY"    sub = "SILKSCREEN_TOP")
            (equal(field_prefix "slkb") group = "BOARD GEOMETRY"    sub = "SILKSCREEN_BOTTOM")
            (equal(field_prefix "reft") group = "REF DES"           sub = "SILKSCREEN_TOP")
            (equal(field_prefix "refb") group = "REF DES"           sub = "SILKSCREEN_BOTTOM")
            (equal(field_prefix "bndt") group = "PACKAGE GEOMETRY"  sub = "PLACE_BOUND_TOP")
            (equal(field_prefix "bndb") group = "PACKAGE GEOMETRY"  sub = "PLACE_BOUND_BOTTOM")
            (equal(field_prefix "rki")  group = "ROUTE KEEPIN"      sub = layer)
            (equal(field_prefix "rko")  group = "ROUTE KEEPOUT"     sub = layer)
            (equal(field_prefix "bound") group = "BOUNDARY"         sub = layer) 
            (equal(field_prefix "anti") group = "ANTI ETCH"        sub = layer)
            (equal(field_prefix "c1")   group = moka_c1_class       sub = moka_c1_sub)
            (equal(field_prefix "c2")   group = moka_c2_class       sub = moka_c2_sub)
            (t group = "ETCH" sub = layer)
        )
        
        if(is_checked then
            if(stringp(group) && strlen(group)>0 && stringp(sub) && strlen(sub)>0 then
                color_idx = moka_get_color_safe(group sub)
            else
                color_idx = 1
            )
        else
            color_idx = 0 
        )
        
        errset(axlFormSetField(form field_name color_idx))
    )
)

defun( moka_refresh_custom_column (form field_prefix col_idx)
    let((row layer)
        for(i 0 length(moka_layer_table)-1
            row = nth(i moka_layer_table)
            layer = nth(0 row)
            moka_update_cell_color(form field_prefix i layer nth(col_idx row))
        )
        errset(axlFormDisplay(form) nil)
        errset(axlFlushDisplay() nil)
    )
)

defun( moka_initialize_custom_selector (form slot class_popup)
    let((class_field sub_field grp sub sub_popup)
        if(slot == 1 then
            class_field = "c1_class"
            sub_field = "c1_sub"
            grp = moka_c1_class
            sub = moka_c1_sub
        else
            class_field = "c2_class"
            sub_field = "c2_sub"
            grp = moka_c2_class
            sub = moka_c2_sub
        )
        unless(stringp(grp) grp = "")
        unless(stringp(sub) sub = "")
        unless(moka_class_exists_safe(grp)
            grp = ""
            sub = ""
        )
        unless(strlen(sub) == 0 || moka_layer_exists_safe(moka_custom_layer_name(grp sub))
            sub = ""
        )
        moka_set_custom_class_sub(slot grp sub)
        axlFormBuildPopup(form class_field class_popup)
        axlFormSetField(form class_field upperCase(grp))
        sub_popup = moka_subclass_popup(grp)
        axlFormBuildPopup(form sub_field sub_popup)
        axlFormSetField(form sub_field upperCase(sub))
    )
)

defun( moka_update_custom_class_selector (form slot)
    let((class_field sub_field prefix col_idx grp old_grp old_sub sub_popup)
        if(slot == 1 then
            class_field = "c1_class"
            sub_field = "c1_sub"
            prefix = "c1"
            col_idx = 15
            old_grp = moka_c1_class
            old_sub = moka_c1_sub
        else
            class_field = "c2_class"
            sub_field = "c2_sub"
            prefix = "c2"
            col_idx = 16
            old_grp = moka_c2_class
            old_sub = moka_c2_sub
        )
        grp = axlFormGetField(form class_field)
        unless(stringp(grp) grp = "")
        unless(stringp(old_grp) old_grp = "")
        unless(stringp(old_sub) old_sub = "")
        if(equal(upperCase(grp) upperCase(old_grp)) then
            unless(moka_layer_exists_safe(moka_custom_layer_name(grp old_sub)) old_sub = "")
        else
            old_sub = ""
        )
        moka_set_custom_class_sub(slot grp old_sub)
        sub_popup = moka_subclass_popup(grp)
        axlFormBuildPopup(form sub_field sub_popup)
        axlFormSetField(form sub_field upperCase(old_sub))
        moka_refresh_custom_column(form prefix col_idx)
    )
)

defun( moka_update_custom_subclass_selector (form slot)
    let((class_field sub_field prefix col_idx grp sub)
        if(slot == 1 then
            class_field = "c1_class"
            sub_field = "c1_sub"
            prefix = "c1"
            col_idx = 15
        else
            class_field = "c2_class"
            sub_field = "c2_sub"
            prefix = "c2"
            col_idx = 16
        )
        grp = axlFormGetField(form class_field)
        sub = axlFormGetField(form sub_field)
        moka_set_custom_class_sub(slot grp sub)
        moka_refresh_custom_column(form prefix col_idx)
    )
)

defun( moka_refdes_set_status (message)
    axlMsgPut(sprintf(nil "Moka skill - \316\273\272\305\271\244\276\337: %s" message))
    message
)

defun( moka_refdes_show_layer (layer_name)
    let((exists)
        exists = errset(axlIsLayer(layer_name) nil)
        when(exists && car(exists)
            errset(axlVisibleLayer(layer_name t) nil)
        )
    )
)

defun( moka_refdes_show_side (side show_place_bound show_vias)
    moka_refdes_show_layer(strcat("BOARD GEOMETRY/SILKSCREEN_" side))
    moka_refdes_show_layer(strcat("PACKAGE GEOMETRY/SILKSCREEN_" side))
    moka_refdes_show_layer(strcat("REF DES/SILKSCREEN_" side))
    moka_refdes_show_layer(strcat("PIN/" side))
    moka_refdes_show_layer(strcat("BOARD GEOMETRY/SOLDERMASK_" side))
    moka_refdes_show_layer(strcat("PACKAGE GEOMETRY/SOLDERMASK_" side))
    moka_refdes_show_layer(strcat("PIN/SOLDERMASK_" side))
    moka_refdes_show_layer(strcat("VIA CLASS/SOLDERMASK_" side))
    when(show_place_bound
        moka_refdes_show_layer(strcat("PACKAGE GEOMETRY/PLACE_BOUND_" side))
    )
    when(show_vias moka_refdes_show_layer(strcat("VIA CLASS/" side)))
)

defun( moka_refdes_set_view_flipped (want_flipped)
    let((result)
        result = errset(axlDesignFlip(want_flipped) nil)
        when(result && car(result)
            moka_refdes_view_flipped = want_flipped
        )
        moka_refdes_view_flipped == want_flipped
    )
)

defun( moka_refdes_show_layers (show_top show_bottom show_place_bound show_vias)
    ; Allegro 16.6 may defer the first visibility change while an enter function is active.
    errset(axlVisibleDesign(nil) nil)
    errset(axlVisibleUpdate(t) nil)
    errset(axlFlushDisplay() nil)
    moka_refdes_show_layer("BOARD GEOMETRY/OUTLINE")
    moka_refdes_show_layer("BOARD GEOMETRY/DESIGN_OUTLINE")
    when(show_top moka_refdes_show_side("TOP" show_place_bound show_vias))
    when(show_bottom moka_refdes_show_side("BOTTOM" show_place_bound show_vias))
    cond(
        (show_top && show_bottom moka_refdes_display_mode = "BOTH")
        (show_bottom moka_refdes_display_mode = "BOTTOM")
        (t moka_refdes_display_mode = "TOP")
    )
    moka_refdes_set_view_flipped(show_bottom && !show_top)
    errset(axlVisibleUpdate(t) nil)
    errset(axlFlushDisplay() nil)
)

defun( moka_refdes_cycle_side (direction)
    let((show_place_bound show_vias show_top)
        show_place_bound = nil
        show_vias = nil
        when(moka_refdesFormHandle
            show_place_bound = moka_refdes_checked_value(axlFormGetField(
                moka_refdesFormHandle "show_place_bound"))
            show_vias = moka_refdes_checked_value(axlFormGetField(
                moka_refdesFormHandle "show_vias"))
        )
        show_top = cond(
            (moka_refdes_display_mode == "TOP" nil)
            (moka_refdes_display_mode == "BOTTOM" t)
            (direction == "prev" t)
            (t nil)
        )
        if(show_top then
            progn(
                moka_refdes_show_layers(t nil show_place_bound show_vias)
                moka_refdes_set_status("\266\245\262\343\316\273\272\305\317\340\271\330\262\343\322\321\317\324\312\276\241\243")
            )
        else
            progn(
                moka_refdes_show_layers(nil t show_place_bound show_vias)
                moka_refdes_set_status("\265\327\262\343\316\273\272\305\317\340\271\330\262\343\322\321\276\265\317\361\317\324\312\276\241\243")
            )
        )
    )
)

defun( moka_refdes_checked_value (value)
    cond(
        (value == t t)
        (numberp(value) value != 0)
        (stringp(value)
            member(upperCase(value) list("1" "T" "TRUE" "ON" "YES"))
        )
        (t nil)
    )
)

defun( moka_refdes_apply_find_filter ()
    unless(moka_refdes_find_filter_saved
        moka_refdes_find_enabled_saved = axlGetFindFilter()
        moka_refdes_find_on_saved = axlGetFindFilter(t)
        moka_refdes_find_filter_saved = t
    )
    axlSetFindFilter(
        ?enabled list("noall" "components" "symbols" "text" "lines" "linesegs")
        ?onButtons list("noall" "components" "symbols" "text" "lines" "linesegs")
    )
)

defun( moka_refdes_restore_find_filter ()
    when(moka_refdes_find_filter_saved
        errset(axlSetFindFilter(
            ?enabled moka_refdes_find_enabled_saved
            ?onButtons moka_refdes_find_on_saved) nil)
        moka_refdes_find_filter_saved = nil
        moka_refdes_find_enabled_saved = nil
        moka_refdes_find_on_saved = nil
    )
)

defun( moka_refdes_normalize_symbol (object)
    let((symbol current count)
        symbol = nil
        current = object
        count = 0
        while(current && !symbol && count < 6
            case(current->objType
                ("symbol" symbol = current)
                ("component"
                    when(current->symbol symbol = current->symbol)
                )
            )
            unless(symbol
                current = current->parent
                count = count + 1
            )
        )
        symbol
    )
)

defun( moka_refdes_symbol_valid (symbol)
    symbol &&
    (symbol->type == "PACKAGE" || symbol->type == "MECHANICAL") &&
    stringp(symbol->refdes) && strlen(symbol->refdes) > 0
)

defun( moka_refdes_collect_symbols (all_components)
    let((symbols object symbol design)
        symbols = nil
        if(all_components then
            design = axlDBGetDesign()
            when(design
                foreach(symbol design->symbols
                    when(moka_refdes_symbol_valid(symbol)
                        symbols = cons(symbol symbols)
                    )
                )
            )
        else
            foreach(object axlGetSelSet()
                symbol = moka_refdes_normalize_symbol(object)
                when(moka_refdes_symbol_valid(symbol) && !memq(symbol symbols)
                    symbols = cons(symbol symbols)
                )
            )
        )
        reverse(symbols)
    )
)

defun( moka_refdes_bbox_union (boxes)
    let((box min_x min_y max_x max_y)
        min_x = 1000000000.0
        min_y = 1000000000.0
        max_x = -1000000000.0
        max_y = -1000000000.0
        foreach(box boxes
            when(box
                min_x = min(min_x car(car(box)))
                min_y = min(min_y cadr(car(box)))
                max_x = max(max_x car(cadr(box)))
                max_y = max(max_y cadr(cadr(box)))
            )
        )
        if(min_x < 1000000000.0 then
            list(list(min_x min_y) list(max_x max_y))
        else
            nil
        )
    )
)

defun( moka_refdes_symbol_layer_bbox (symbol layer_name)
    let((boxes)
        boxes = nil
        foreach(child symbol->children
            when(stringp(child->layer) &&
                 upperCase(child->layer) == upperCase(layer_name) &&
                 child->bBox
                boxes = cons(child->bBox boxes)
            )
        )
        moka_refdes_bbox_union(boxes)
    )
)

defun( moka_refdes_symbol_pin_bbox (symbol)
    let((boxes)
        boxes = nil
        foreach(pin symbol->pins
            when(pin->bBox boxes = cons(pin->bBox boxes))
        )
        moka_refdes_bbox_union(boxes)
    )
)

defun( moka_refdes_symbol_center (symbol side)
    let((box)
        box = moka_refdes_symbol_layer_bbox(
            symbol strcat("PACKAGE GEOMETRY/PLACE_BOUND_" side))
        unless(box
            box = moka_refdes_symbol_layer_bbox(
                symbol strcat("PACKAGE GEOMETRY/SILKSCREEN_" side))
        )
        unless(box box = moka_refdes_symbol_pin_bbox(symbol))
        unless(box box = symbol->bBox)
        if(box then
            list(
                (car(car(box)) + car(cadr(box))) / 2.0
                (cadr(car(box)) + cadr(cadr(box))) / 2.0)
        else
            symbol->xy
        )
    )
)

defun( moka_refdes_adjust_text (text target center_refdes horizontal text_block)
    let((ok box_result box text_center delta move_result orientation_result orientation change_result)
        ok = if(text && target && text->xy then t else nil)
        when(ok
            orientation_result = errset(axlTextOrientationCopy(text) nil)
            if(orientation_result && car(orientation_result) then
                orientation = car(orientation_result)
                when(center_refdes orientation->justify = "center")
                when(horizontal orientation->rotation = 0.0)
                when(numberp(text_block) && text_block > 0
                    orientation->textBlock = sprintf(nil "%d" text_block)
                )
                change_result = errset(axlDBChangeText(text nil orientation) nil)
                unless(change_result && car(change_result) ok = nil)
            else
                ok = nil
            )
        )
        when(ok && center_refdes
            box_result = errset(axlDBGetExtents(text nil) nil)
            box = if(box_result && car(box_result) then car(box_result) else text->bBox)
            text_center = if(box then
                list(
                    (car(car(box)) + car(cadr(box))) / 2.0
                    (cadr(car(box)) + cadr(cadr(box))) / 2.0)
            else
                text->xy
            )
            delta = list(
                car(target) - car(text_center)
                cadr(target) - cadr(text_center)
            )
            when(car(delta) != 0.0 || cadr(delta) != 0.0
                move_result = errset(axlTransformObject(text ?move delta) nil)
                unless(move_result && car(move_result) ok = nil)
            )
        )
        ok
    )
)

defun( moka_refdes_first_dbid (value)
    let((found item)
        found = nil
        when(value
            if(axlIsDBIDType(value) then
                found = value
            else
                when(listp(value)
                    foreach(item value
                        unless(found found = moka_refdes_first_dbid(item))
                    )
                )
            )
        )
        found
    )
)

defun( moka_refdes_create_text (symbol layer_name target text_block)
    let((orientation block mirrored result)
        block = if(numberp(text_block) && text_block > 0 then text_block else 3)
        mirrored = if(symbol->isMirrored then t else nil)
        orientation = make_axlTextOrientation(
            ?textBlock sprintf(nil "%d" block)
            ?rotation 0.0
            ?mirrored mirrored
            ?justify "center"
        )
        result = errset(
            axlDBCreateText(symbol->refdes target orientation layer_name symbol)
            nil
        )
        moka_refdes_first_dbid(result)
    )
)

defun( moka_refdes_process_symbol (symbol create_missing center_refdes horizontal text_block)
    let((side silk_layer target texts text layer created_text found_silk adjusted created failed)
        side = if(symbol->isMirrored then "BOTTOM" else "TOP")
        silk_layer = strcat("REF DES/SILKSCREEN_" side)
        target = moka_refdes_symbol_center(symbol side)
        adjusted = 0
        created = 0
        failed = 0
        found_silk = nil
        texts = axlDBGetAttachedText(symbol)
        foreach(text texts
            layer = upperCase(text->layer || "")
            when(layer == silk_layer
                found_silk = t
                when(center_refdes || horizontal ||
                     (numberp(text_block) && text_block > 0)
                    if(moka_refdes_adjust_text(
                        text target center_refdes horizontal text_block) then
                        adjusted = adjusted + 1
                    else
                        failed = failed + 1
                    )
                )
            )
        )
        when(create_missing && !found_silk
            created_text = moka_refdes_create_text(
                symbol silk_layer target text_block)
            if(created_text then
                created = created + 1
                when(center_refdes
                    if(moka_refdes_adjust_text(
                        created_text target t nil 0) then
                        adjusted = adjusted + 1
                    else
                        failed = failed + 1
                    )
                )
            else
                failed = failed + 1
            )
        )
        list(adjusted created failed)
    )
)

defun( moka_refdes_apply (all_components create_missing center_refdes horizontal text_block)
    let((symbols mark result adjusted created failed)
        symbols = moka_refdes_collect_symbols(all_components)
        if(!symbols then
            moka_refdes_set_status("\316\264\321\241\324\361\310\316\272\316\306\367\274\376\241\243")
        else
            mark = axlDBTransactionStart()
            adjusted = 0
            created = 0
            failed = 0
            foreach(symbol symbols
                result = moka_refdes_process_symbol(
                    symbol create_missing center_refdes horizontal text_block)
                adjusted = adjusted + nth(0 result)
                created = created + nth(1 result)
                failed = failed + nth(2 result)
            )
            if(adjusted + created > 0 then
                when(mark axlDBTransactionCommit(mark))
                axlVisibleUpdate(t)
                moka_refdes_set_status(sprintf(
                    nil
                    "\322\321\264\246\300\355 %d \270\366\306\367\274\376\243\254\265\367\325\373 %d \270\366\316\273\272\305\243\254\262\271\306\353 %d \270\366\243\254\312\247\260\334 %d \270\366\241\243"
                    length(symbols) adjusted created failed))
            else
                when(mark axlDBTransactionRollback(mark))
                if(failed > 0 then
                    moka_refdes_set_status(sprintf(
                        nil
                        "\316\273\272\305\264\246\300\355\312\247\260\334 %d \270\366\243\254\307\353\274\354\262\351\306\367\274\376\316\273\272\305\272\315\313\277\323\241\262\343\241\243"
                        failed))
                else
                    moka_refdes_set_status("\303\273\323\320\277\311\264\246\300\355\265\304\316\273\272\305\241\243")
                )
            )
            axlClearSelSet()
        )
    )
)

defun( moka_refdes_create_form_file ()
    let((file port)
        file = axlTempFile(t)
        port = outfile(file)
        if(port then
            fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\n")
            fprintf(port "FORM\nFIXED\nPORT 32 32\n")
            fprintf(port "HEADER \"Moka skill v1.0 - \316\273\272\305\271\244\276\337\"\n")
            fprintf(port "TILE\n")
            fprintf(port "GROUP \"\317\324\312\276\311\350\326\303\"\nGLOC 1 1\nGSIZE 29 11\nENDGROUP\n")
            fprintf(port "FIELD show_top\nFLOC 2 3\nMENUBUTTON \"\317\324\312\276\266\245\262\343\" 12 3\nENDFIELD\n")
            fprintf(port "FIELD show_bottom\nFLOC 16 3\nMENUBUTTON \"\317\324\312\276\265\327\262\343\" 12 3\nENDFIELD\n")
            fprintf(port "FIELD show_both\nFLOC 2 6\nMENUBUTTON \"\317\324\312\276\313\253\303\346\" 26 3\nENDFIELD\n")
            fprintf(port "FIELD show_place_bound\nFLOC 2 10\nCHECKLIST \"Place Bound\"\nENDFIELD\n")
            fprintf(port "FIELD show_vias\nFLOC 16 10\nCHECKLIST \"\317\324\312\276\271\375\277\327\"\nENDFIELD\n")
            fprintf(port "GROUP \"\316\273\272\305\265\367\325\373\"\nGLOC 1 13\nGSIZE 29 14\nENDGROUP\n")
            fprintf(port "FIELD all_components\nFLOC 2 15\nCHECKLIST \"\310\253\262\277\306\367\274\376\"\nENDFIELD\n")
            fprintf(port "FIELD horizontal\nFLOC 16 15\nCHECKLIST \"\313\256\306\275\320\375\327\252\"\nENDFIELD\n")
            fprintf(port "FIELD create_missing\nFLOC 2 18\nCHECKLIST \"\262\271\306\353\310\261\312\247\316\273\272\305\"\nENDFIELD\n")
            fprintf(port "FIELD center_refdes\nFLOC 16 18\nCHECKLIST \"\276\323\326\320\316\273\272\305\"\nENDFIELD\n")
            fprintf(port "TEXT \"\327\326\314\345\243\250\060\075\261\243\263\326\243\251\243\272\"\nTLOC 2 21\nENDTEXT\n")
            fprintf(port "FIELD text_block\nFLOC 20 21\nINTFILLIN 6 3\nMIN 0\nMAX 999\nENDFIELD\n")
            fprintf(port "FIELD apply_refdes\nFLOC 2 24\nMENUBUTTON \"\323\246\323\303\" 26 3\nENDFIELD\n")
            fprintf(port "FIELD done\nFLOC 20 28\nMENUBUTTON \"\271\330\261\325\" 9 3\nENDFIELD\n")
            fprintf(port "ENDTILE\nENDFORM\n")
            close(port)
            file
        else
            nil
        )
    )
)

defun( moka_refdes_stop_enter ()
    let((result)
        moka_refdes_active = nil
        result = errset(axlCancelEnterFun() nil)
        unless(result && car(result)
            errset(axlFinishEnterFun() nil)
        )
        t
    )
)

defun( moka_refdes_form_cb (form)
    let((field show_place_bound show_vias text_block)
        if(form->doneState > 0 then
            moka_refdes_stop_enter()
        else
            field = form->curField
            show_place_bound = moka_refdes_checked_value(
                axlFormGetField(form "show_place_bound"))
            show_vias = moka_refdes_checked_value(
                axlFormGetField(form "show_vias"))
            case(field
                ("show_top"
                    moka_refdes_show_layers(t nil show_place_bound show_vias)
                    moka_refdes_set_status("\266\245\262\343\316\273\272\305\317\340\271\330\262\343\322\321\317\324\312\276\241\243")
                )
                ("show_bottom"
                    moka_refdes_show_layers(nil t show_place_bound show_vias)
                    moka_refdes_set_status("\265\327\262\343\316\273\272\305\317\340\271\330\262\343\322\321\276\265\317\361\317\324\312\276\241\243")
                )
                ("show_both"
                    moka_refdes_show_layers(t t show_place_bound show_vias)
                    moka_refdes_set_status("\313\253\303\346\316\273\272\305\317\340\271\330\262\343\322\321\317\324\312\276\241\243")
                )
                ("apply_refdes"
                    text_block = axlFormGetField(form "text_block")
                    unless(numberp(text_block) text_block = atoi(text_block || "0"))
                    moka_refdes_apply(
                        moka_refdes_checked_value(
                            axlFormGetField(form "all_components"))
                        moka_refdes_checked_value(
                            axlFormGetField(form "create_missing"))
                        moka_refdes_checked_value(
                            axlFormGetField(form "center_refdes"))
                        moka_refdes_checked_value(
                            axlFormGetField(form "horizontal"))
                        text_block)
                )
                ("done"
                    moka_refdes_stop_enter()
                )
            )
        )
        t
    )
)

(defun moka_refdes_done ()
    moka_refdes_active = nil
    errset(axlCancelEnterFun() nil)
    t
)

(defun moka_refdes_cancel ()
    moka_refdes_active = nil
    errset(axlCancelEnterFun() nil)
    t
)

defun( moka_refdes_ui_open ()
    let((form_file form point)
        moka_refdes_active = t
        unwindProtect(
            progn(
            moka_refdes_apply_find_filter()
            axlClearSelSet()
            form_file = moka_refdes_create_form_file()
            if(form_file then
                form = axlMiniStatusLoad(
                    gensym() form_file 'moka_refdes_form_cb)
                when(isFile(form_file) errset(axlTempFileRemove(form_file) nil))
                if(form then
                    moka_refdesFormHandle = form
                    axlFormSetField(form "show_place_bound" nil)
                    axlFormSetField(form "show_vias" nil)
                    axlFormSetField(form "all_components" nil)
                    axlFormSetField(form "create_missing" nil)
                    axlFormSetField(form "center_refdes" nil)
                    axlFormSetField(form "horizontal" nil)
                    axlFormSetField(form "text_block" 0)
                    moka_refdes_show_layers(t nil nil nil)
                    errset(axlControlRaise('options) nil)
                    while(moka_refdes_active &&
                          (point = axlEnterPoint(
                              ?prompts list("\321\241\324\361\306\367\274\376\241\242\316\273\272\305\316\304\327\326\273\362\313\277\323\241\317\337\243\273\312\271\323\303\303\346\260\345\262\331\327\367\243\254\323\322\274\374 Done \315\313\263\366\241\243")))
                        axlAddSelectPoint(point)
                    )
                else
                    moka_refdes_active = nil
                    moka_refdes_set_status("\316\336\267\250\264\264\275\250\316\273\272\305\271\244\276\337\303\346\260\345\241\243")
                )
            else
                moka_refdes_active = nil
                moka_refdes_set_status("\316\336\267\250\264\264\275\250\316\273\272\305\271\244\276\337\303\346\260\345\241\243")
            )
            )
            progn(
                moka_refdes_active = nil
                moka_refdesFormHandle = nil
                moka_refdes_restore_find_filter()
                axlClearSelSet()
            )
        )
        t
    )
)

defun( moka_cmd_ui ()
    moka_sync_table()
    let((formFile form row class_popup)
        if(moka_mainFormHandle then
            errset(axlFormClose(moka_mainFormHandle) nil)
            moka_mainFormHandle = nil
        else
            formFile = moka_create_form_file()
            if(formFile then 
            form = axlFormCreate(gensym() formFile nil 'moka_form_cb t)
            
            if(null(form) then
                ; 无法创建表单文件，Allegro加载失败:
                axlMsgPut("FATAL ERROR: \316\336\267\250\264\264\275\250\261\355\265\245\316\304\274\376\243\254Allegro\274\323\324\330\312\247\260\334: %s" formFile)
            else
                moka_mainFormHandle = form
                class_popup = moka_class_popup()
                moka_initialize_custom_selector(form 1 class_popup)
                moka_initialize_custom_selector(form 2 class_popup)
                
                for(i 0 length(moka_layer_table)-1
                    let((ln prefixes)
                        row = nth(i moka_layer_table)
                        ln = nth(0 row)
                        prefixes = list("en" "pin" "via" "drc" "mst" "msb" "slkt" "slkb" "reft" "refb" "bndt" "bndb" "rki" "rko" "c1" "c2" "bound" "anti")
                        
                        for(k 1 18
                            moka_update_cell_color(form nth(k-1 prefixes) i ln nth(k row))
                        )
                    )
                )
                
                axlFormDisplay(form)  
                deleteFile(formFile)
            )
        )
        )
    )
)

defun( moka_form_cb (form)
    case(form->curField
        ("btn_apply"
            moka_set_custom_class_sub(
                1 axlFormGetField(form "c1_class") axlFormGetField(form "c1_sub"))
            moka_set_custom_class_sub(
                2 axlFormGetField(form "c2_class") axlFormGetField(form "c2_sub"))
            moka_save_config_ini()
            axlFormClose(form)
        )

        ("c1_class" moka_update_custom_class_selector(form 1))

        ("c1_sub" moka_update_custom_subclass_selector(form 1))

        ("c2_class" moka_update_custom_class_selector(form 2))

        ("c2_sub" moka_update_custom_subclass_selector(form 2))
        
        ("btn_close" axlFormClose(form))
        
        ("btn_ta" Run_TraceAnalyzerTool())

        ("btn_pin_swap" axlShellPost("moka_pin_swap"))

        ("btn_dp_antipad" axlShellPost("moka_dp_antipad"))

        ("btn_refdes" axlShellPost("moka_refdes"))
        
        (t
            let((all_fields base_name field_name idx ln prefixes col_idx old_state new_state row)
                field_name = form->curField
                all_fields = list("all_en" "all_pin" "all_via" "all_drc" "all_mst" "all_msb" "all_slkt" "all_slkb" "all_reft" "all_refb" "all_bndt" "all_bndb" "all_rki" "all_rko" "all_c1" "all_c2" "all_bound" "all_anti")
                prefixes = list("en" "pin" "via" "drc" "mst" "msb" "slkt" "slkb" "reft" "refb" "bndt" "bndb" "rki" "rko" "c1" "c2" "bound" "anti")
                
                if(member(field_name all_fields) then
                    base_name = substring(field_name 5) 
                    
                    col_idx = 0
                    for(c 1 18 if(equal(nth(c-1 prefixes) base_name) then col_idx = c))
                    
                    let((first_row target_state)
                        first_row = nth(0 moka_layer_table)
                        old_state = nth(col_idx first_row)
                        target_state = if(old_state == "1" || old_state == t then nil else t)
                        
                        for(i 0 length(moka_layer_table)-1
                            ln = nth(0 nth(i moka_layer_table))
                            row = nth(i moka_layer_table)
                            row = ntheplace(row target_state col_idx)
                            moka_layer_table = ntheplace(moka_layer_table row i)
                            moka_update_cell_color(form base_name i ln target_state)
                        )
                        
                        errset(axlFormSetField(form field_name 0))
                    )
                else
                    foreach(pfx prefixes
                        if(rexMatchp(strcat("^" pfx "_") field_name) then
                            idx = atoi(substring(field_name strlen(pfx)+2))
                            if(integerp(idx) then
                                col_idx = 0
                                for(c 1 18 if(equal(nth(c-1 prefixes) pfx) then col_idx = c))
                                
                                ln = nth(0 nth(idx moka_layer_table))
                                row = nth(idx moka_layer_table)
                                
                                old_state = nth(col_idx row)
                                new_state = if(old_state == "1" || old_state == t then nil else t)
                                
                                row = ntheplace(row new_state col_idx)
                                moka_layer_table = ntheplace(moka_layer_table row idx)
                                moka_update_cell_color(form pfx idx ln new_state)
                            )
                        )
                    )
                )
                
                errset(axlFormDisplay(form) nil)
                errset(axlFlushDisplay() nil)
            )
        )
    )
    if(form->doneState > 0 then
        moka_mainFormHandle = nil
    )
)

defun( ntheplace (lst val n)
    let((new_lst)
        new_lst = nil
        for(i 0 length(lst)-1
            if(i == n then new_lst = cons(val new_lst) else new_lst = cons(nth(i lst) new_lst))
        )
        reverse(new_lst)
    )
)

; ==============================================================================
; ========================= MOKA DESIGN STATUS MODULE ==========================
; ==============================================================================

defun( moka_get_seconds_since_midnight ()
    let( (time_str parts time_parts total_seconds)
        time_str = getCurrentTime()
        parts = parseString(time_str " ")
        total_seconds = 0
        
        foreach( part parts
            if( index(part ":") != nil then
                time_parts = parseString(part ":")
                if( length(time_parts) == 3 then
                    total_seconds = (atoi(nth(0 time_parts)) * 3600) + (atoi(nth(1 time_parts)) * 60) + atoi(nth(2 time_parts))
                )
            )
        )
        total_seconds
    )
)

defun( moka_get_date_string ()
    let( (time_str parts date_str)
        time_str = getCurrentTime()
        parts = parseString(time_str " ")
        date_str = ""
        
        foreach( part parts
            if( index(part ":") == nil then
                date_str = strcat(date_str part " ")
            )
        )
        date_str
    )
)

unless(boundp('G_MokaSessionStartTime)
    G_MokaSessionStartTime = moka_get_seconds_since_midnight()
)

defun( moka_cmd_get_status ()
    let( (pin_count rats_count rats_list currentTime sessionElapsed logFile inPort outPort line parts logDate logSeconds todayDate totalSeconds hours mins secs time_str)

        currentTime = moka_get_seconds_since_midnight()
        sessionElapsed = currentTime - G_MokaSessionStartTime
        
        if( sessionElapsed < 0 then
            sessionElapsed = 0
        )

        todayDate = moka_get_date_string()
        logFile = strcat(moka_install_dir "/moka_daily_time.log")
        logFile = buildString(parseString(logFile "\\") "/")
        
        logSeconds = 0
        logDate = ""

        if(isFile(logFile) then
            inPort = infile(logFile)
            if(inPort then
                gets(line inPort)
                if(line then
                    parts = parseString(line "|")
                    if(length(parts) >= 2 then
                        logDate = car(parts)
                        logSeconds = atoi(cadr(parts))
                    )
                )
                close(inPort)
            )
        )

        if(logDate == todayDate then
            totalSeconds = logSeconds + sessionElapsed
        else
            totalSeconds = sessionElapsed
        )

        outPort = outfile(logFile)
        if(outPort then
            fprintf(outPort "%s|%d\n" todayDate totalSeconds)
            close(outPort)
        )

        G_MokaSessionStartTime = currentTime

        hours = totalSeconds / 3600
        mins = (totalSeconds - (hours * 3600)) / 60
        secs = totalSeconds - (hours * 3600) - (mins * 60)
        ; 小时 分钟 秒
        time_str = sprintf(nil "%d \320\241\312\261 %d \267\326\326\323 %d \303\353" hours mins secs)

        pin_count = 0
        foreach(sym axlDBGetDesign()->symbols
            if(sym->type == "PACKAGE" || sym->type == "MECHANICAL" then
                pin_count = pin_count + length(sym->pins)
            )
        )

        axlClearSelSet()
        axlSetFindFilter(?enabled list("noall" "ratsnests") ?onButtons list("noall" "ratsnests"))
        axlAddSelectAll()
        
        rats_list = axlGetSelSet()
        rats_count = length(rats_list)
        
        axlClearSelSet()

        axlMsgPut("-------------------------------------------------")
        ; 设计状态数据:
        axlMsgPut("Moka Skill v1.0 \311\350\274\306\327\264\314\254\312\375\276\335:")
        ; 总管脚数
        axlMsgPut("\327\334\271\334\275\305\312\375            : %d" pin_count)
        ; 剩余未连接飞线数
        axlMsgPut("\312\243\323\340\316\264\301\254\275\323\267\311\317\337\312\375    : %d" rats_count)
        ; 今日总设计耗时
        axlMsgPut("\275\361\310\325\327\334\311\350\274\306\272\304\312\261      : %s" time_str)
        axlMsgPut("-------------------------------------------------")

        ; PCB 设计状态: 总管脚数: 剩余飞线数: 今日总耗时:
        axlUIConfirm(sprintf(nil "Moka Skill v1.0 PCB \311\350\274\306\327\264\314\254:\n\n> \327\334\271\334\275\305\312\375: %d\n> \312\243\323\340\267\311\317\337\312\375: %d\n> \275\361\310\325\327\334\272\304\312\261: %s" pin_count rats_count time_str))
    )
)


; ==============================================================================
; ===================== TRACE ANALYZER INTEGRATED MODULE =======================
; ==============================================================================

defun( Create_TA_Main_Form ()
    let((formFile outPort)
        formFile = "./ta_main.form"
        outPort = outfile(formFile)
        
        fprintf(outPort "FILE_TYPE=FORM_DEFN VERSION=2\n")
        fprintf(outPort "FORM\n")
        fprintf(outPort "FIXED\n")
        fprintf(outPort "PORT 48 30\n") 
        ; 走线分析器
        fprintf(outPort "HEADER \"Moka skill v1.0 - \327\337\317\337\267\326\316\366\306\367\"\n")
        fprintf(outPort "TILE\n")
    
        ; 控制面板
        fprintf(outPort "GROUP \"\277\330\326\306\303\346\260\345\"\n")
        fprintf(outPort "GLOC 2 1\n")
        fprintf(outPort "GSIZE 44 8\n")
        fprintf(outPort "ENDGROUP\n")
        
        fprintf(outPort "FIELD btn_scan\n")
        fprintf(outPort "FLOC 4 3\n")
        ; 扫描
        fprintf(outPort "MENUBUTTON \"\311\250\303\350\" 10 3\n")
        fprintf(outPort "ENDFIELD\n")
    
        fprintf(outPort "FIELD btn_clear\n")
        fprintf(outPort "FLOC 16 3\n")
        ; 清除
        fprintf(outPort "MENUBUTTON \"\307\345\263\375\" 10 3\n")
        fprintf(outPort "ENDFIELD\n")
        
        fprintf(outPort "FIELD btn_zoom\n")
        fprintf(outPort "FLOC 28 3\n")
        ; 跳转
        fprintf(outPort "MENUBUTTON \"\314\370\327\252\" 10 3\n")
        fprintf(outPort "ENDFIELD\n")
        
        ; 颜色:
        fprintf(outPort "TEXT \"\321\325\311\253:\"\n")
        fprintf(outPort "TLOC 4 6\n")
        fprintf(outPort "ENDTEXT\n")
        
        fprintf(outPort "FIELD current_color\n")
        fprintf(outPort "FLOC 8 6\n")
        fprintf(outPort "INTFILLIN 4 3\n")
        fprintf(outPort "MIN 0\n")
        fprintf(outPort "MAX 255\n")
        fprintf(outPort "ENDFIELD\n")
        
        fprintf(outPort "FIELD btn_palette\n")
        fprintf(outPort "FLOC 18 6\n")
        ; 设置颜色
        fprintf(outPort "MENUBUTTON \"\311\350\326\303\321\325\311\253\" 20 3\n")
        fprintf(outPort "ENDFIELD\n")
        
        ; 网络走线列表
        fprintf(outPort "GROUP \"\315\370\302\347\327\337\317\337\301\320\261\355\"\n")
        fprintf(outPort "GLOC 2 10\n")
        fprintf(outPort "GSIZE 44 19\n")
        fprintf(outPort "ENDGROUP\n")
 
        fprintf(outPort "FIELD result_list\n")
        fprintf(outPort "FLOC 4 12\n")
        fprintf(outPort "LIST \"\" 40 9\n")
        fprintf(outPort "OPTIONS multiselect\n")
        fprintf(outPort "ENDFIELD\n")
        
        fprintf(outPort "ENDTILE\n")
        fprintf(outPort "ENDFORM\n")
        close(outPort)
       
        formFile
    )
)

defun( Create_TA_Palette_Form ()
    let((formFile outPort row col x y)
        formFile = "./ta_palette.form"
        outPort = outfile(formFile)
        
        fprintf(outPort "FILE_TYPE=FORM_DEFN VERSION=2\n")
        fprintf(outPort "FORM\n")
        fprintf(outPort "FIXED\n")
        fprintf(outPort "PORT 70 20\n") 
        ; 调色板
        fprintf(outPort "HEADER \"Moka skill v1.0 - \265\367\311\253\260\345\"\n")
  
        fprintf(outPort "TILE\n")
        
        for(i 1 96
            row = (i - 1) / 16
            col = (i - 1) - row * 16
            
            x = 2 + col * 4  
     
            y = 1 + row * 3 
            
            fprintf(outPort "FIELD box_%d\n" i)
            fprintf(outPort "FLOC %d %d\n" x y)
            fprintf(outPort "COLOR 3 2\n") 
            fprintf(outPort "ENDFIELD\n")
        )
     
        fprintf(outPort "ENDTILE\n")
        fprintf(outPort "ENDFORM\n")
        close(outPort)
        
        formFile
    )
)

defun( TA_Process_Net_Segments (target_net target_w target_layer action c_idx)
    let((nets netName w layerName tolerance minX minY maxX maxY matchedCount resultBox)
        tolerance = 0.001
        minX = 9999999.0 minY = 9999999.0 maxX = -9999999.0 maxY = -9999999.0
        matchedCount = 0

        if(target_net == "DUMMY_NET" then
            nets = setof(n axlDBGetDesign()->nets n->name == nil || n->name == "")
 
        else
            nets = list(axlDBFindByName('net target_net))
        )

        foreach(net nets
            if(net then
                foreach(branch net->branches
                    foreach(child branch->children
          
                      if(child->objType == "path" then
                            foreach(seg child->segments
                                layerName = seg->layer
                    
                                if(rexMatchp("^ETCH/" layerName) then
                                    layerName = substring(layerName 6)
                                    w = seg->width
         
                                    if(w && numberp(w) && abs(w - target_w) < tolerance && layerName == target_layer then
                        
                                        if(action == "highlight" then
                                         
                                            if(c_idx && c_idx > 0 then
                                                errset(axlCustomColorObject(net c_idx) nil)
                                          
                                            else
                                                errset(axlHighlightObject(seg) nil)
                                            )
     
                                        else 
                                            if(action == "dehighlight" then
                 
                                                errset(axlClearObjectCustomColor(net) nil)
                                                errset(axlDehighlightObject(seg) nil)
                   
                                            )
                                        )
                                   
                                        matchedCount++
                                        if(seg->bBox then
              
                                            if(caar(seg->bBox) < minX then minX = caar(seg->bBox))
                                            if(cadar(seg->bBox) < minY then minY = cadar(seg->bBox))
              
                                            if(caadr(seg->bBox) > maxX then maxX = caadr(seg->bBox))
                                            if(cadadr(seg->bBox) > maxY then maxY = cadadr(seg->bBox))
              
                                        )
                                    )
                                )
      
                            )
                        )
                    )
                )
            )
      
        )

        if(minX != 9999999.0 then resultBox = list(minX minY maxX maxY) else resultBox = nil)
        list(matchedCount resultBox)
    )
)

defun( TA_Clear_All ()
    if(ta_lastKeys then
        foreach(key ta_lastKeys
            let((crit)
                crit = ta_dbTable[key]
                if(crit then TA_Process_Net_Segments(nth(1 crit) nth(0 crit) nth(2 crit) "dehighlight" nil))
            )
        )
  
        ta_lastKeys = nil
    )
)

defun( TA_Zoom_To_Keys (keys)
    let((minX minY maxX maxY box expand res localBox crit validCount)
        minX = 9999999.0 minY = 9999999.0 maxX = -9999999.0 maxY = -9999999.0
        validCount = 0
        
        foreach(key keys
            crit = ta_dbTable[key]
            if(crit then
                res = TA_Process_Net_Segments(nth(1 crit) nth(0 crit) nth(2 crit) "bbox_only" nil)
                localBox = nth(1 res)
                if(localBox then
                    validCount++
                   
                    if(nth(0 localBox) < minX then minX = nth(0 localBox))
                    if(nth(1 localBox) < minY then minY = nth(1 localBox))
                    if(nth(2 localBox) > maxX then maxX = nth(2 localBox))
                    if(nth(3 localBox) > maxY then maxY = nth(3 localBox))
       
                 )
            )
        )
        
        if(minX != 9999999.0 then
            expand = max(abs(maxX - minX)*0.1 abs(maxY - minY)*0.1 50.0)
            box = list(minX - expand:minY - expand  maxX + expand:maxY + expand)
        
            if(errset(axlWindowBox(box) nil) == nil then errset(axlWindowBoxSet(box) nil))
        )
    )
)

defun( TA_Handle_Selection (doZoom)
    let((selItems c_idx crit val)
        if(ta_mainFormHandle then
            selItems = axlFormListGetSelItems(ta_mainFormHandle "result_list")
            TA_Clear_All()
            
            if(selItems then
                if(stringp(selItems) then selItems = list(selItems))
    
                val = axlFormGetField(ta_mainFormHandle "current_color")
                if(val == 0 then c_idx = nil else c_idx = val)
                
                foreach(item selItems
          
                    if(ta_dbTable[item] then
                        crit = ta_dbTable[item]
                        TA_Process_Net_Segments(nth(1 crit) nth(0 crit) nth(2 crit) "highlight" c_idx)
                        ta_lastKeys = cons(item ta_lastKeys)
     
                     )
                )
                
                if(doZoom && ta_lastKeys then TA_Zoom_To_Keys(ta_lastKeys))
            )
        )
    )
)

defun( TA_Scan_Visible_Traces (formHandle)
    let((w netName layerName key listItems)
        ta_dbTable = makeTable(symbolToString(gensym()) nil)
        ta_lastKeys = nil
        listItems = nil

        foreach(net axlDBGetDesign()->nets
            netName = if(net->name && net->name != "" then net->name else "DUMMY_NET")
            foreach(branch net->branches
          
                foreach(child branch->children
                    if(child->objType == "path" then
                        foreach(seg child->segments
                            layerName = seg->layer
               
                            if(rexMatchp("^ETCH/" layerName) && axlIsVisibleLayer(seg->layer) then
                                layerName = substring(layerName 6)
                                w = seg->width
              
                                if(w && numberp(w) then
                                    key = sprintf(nil "W:%-6.3f | Net: %-15s | L: %s" w netName layerName)
                                    if(!ta_dbTable[key] then
                                        ta_dbTable[key] = list(w netName layerName)
               
                                         listItems = cons(key listItems)
                                    )
                                )
    
                            )
                        )
                    )
                )
            )
    
        )
        
        if(ta_lastListItems then
            foreach(oldItem ta_lastListItems
                errset(axlFormListDeleteItem(formHandle "result_list" oldItem) nil)
            )
        )
        for(i 1 50 errset(axlFormListDeleteItem(formHandle "result_list" 0) nil))
        
     
        if(listItems then
            listItems = sort(listItems 'alphalessp)
            foreach(item listItems
                axlFormListAddItem(formHandle "result_list" item -1)
            )
            ta_lastListItems = listItems 
            ; 状态: 扫描完成。共发现 %d 条不同宽度的走线。
            axlMsgPut("\327\264\314\254: \311\250\303\350\315\352\263\311\241\243\271\262\267\242\317\326 %d \314\365\262\273\315\254\277\355\266\310\265\304\327\337\317\337\241\243" length(listItems))
        else
            ta_lastListItems = nil
            ; 状态: 当前可见层上未发现任何走线。
            axlMsgPut("\327\264\314\254: \265\261\307\260\277\311\274\373\262\343\311\317\316\264\267\242\317\326\310\316\272\316\327\337\317\337\241\243")
        )
    )
)

defun( Run_TA_Palette_Drawer ()
    let((pFormFile)
        pFormFile = Create_TA_Palette_Form()
        ta_paletteFormHandle = axlFormCreate((gensym) pFormFile '(e "outer") 'TA_Palette_Callback t)
     
        if(ta_paletteFormHandle then
            for(i 1 96 errset(axlFormSetField(ta_paletteFormHandle sprintf(nil "box_%d" i) i) nil))
            axlFormDisplay(ta_paletteFormHandle)
        )
        if(isFile(pFormFile) then deleteFile(pFormFile))
    )
)

defun( TA_Palette_Callback (form)
    let((field c_idx)
        field = form->curField
        
        if(strncmp(field "box_" 4) == 0 then
    
            c_idx = atoi(substring(field 5))
            if(c_idx && ta_mainFormHandle then
                axlFormSetField(ta_mainFormHandle "current_color" c_idx)
                TA_Handle_Selection(nil)
            )
        )
    )
    
    if(form->doneState > 0 then
     
        ta_paletteFormHandle = nil
    )
)

defun( TA_Main_Callback (form)
    let((field)
        field = form->curField
        
        case(field
            ("btn_scan"
                TA_Clear_All()
                TA_Scan_Visible_Traces(form)
            )
   
            ("btn_clear"
                TA_Clear_All()
                errset(axlFormListDeselectItem(form "result_list" 'all) nil)
                axlFormSetField(form "current_color" 0)
                ; 状态: 高亮已全部清除。
                axlMsgPut("\327\264\314\254: \270\337\301\301\322\321\310\253\262\277\307\345\263\375\241\243")
            )
        
            ("btn_zoom"
                if(ta_lastKeys then TA_Zoom_To_Keys(ta_lastKeys))
            )
            
            ("btn_palette"
                if(ta_paletteFormHandle then
                    errset(axlFormClose(ta_paletteFormHandle) nil)
    
                    ta_paletteFormHandle = nil
                else
                    Run_TA_Palette_Drawer()
                )
            )
            
      
            ("current_color"
                TA_Handle_Selection(nil)
            )
            
            ("result_list"
                TA_Handle_Selection(t)
            )
        )
    )
  
    
    if(form->doneState > 0 then
        if(ta_paletteFormHandle then 
            errset(axlFormClose(ta_paletteFormHandle) nil)
        )
        ta_mainFormHandle = nil
        ta_paletteFormHandle = nil
    )
)

defun( Run_TraceAnalyzerTool ()
    let((formFile)
        if(ta_mainFormHandle then
            if(ta_paletteFormHandle then errset(axlFormClose(ta_paletteFormHandle) nil))
            errset(axlFormClose(ta_mainFormHandle) nil)
            ta_mainFormHandle = nil
            ta_paletteFormHandle = nil
        else
        
        formFile = Create_TA_Main_Form()
        ta_mainFormHandle = axlFormCreate( (gensym) formFile '(e "outer") 'TA_Main_Callback t)
        
        if(ta_mainFormHandle then
        
            axlFormSetField(ta_mainFormHandle "current_color" 0)
            axlFormDisplay(ta_mainFormHandle)
            TA_Scan_Visible_Traces(ta_mainFormHandle)
        else
            ; 错误: 无法创建分析器主界面。
            axlMsgPut("\264\355\316\363: \316\336\267\250\264\264\275\250\267\326\316\366\306\367\326\367\275\347\303\346\241\243")
        )
        
            if(isFile(formFile) then deleteFile(formFile))
        )
    )
)
