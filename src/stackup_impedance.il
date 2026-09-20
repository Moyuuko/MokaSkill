/*
  Moka Skill Stackup / Impedance Module v1.0

  Commands:
    moka_stackup_impedance - open the control panel
    moka_stackup_export    - export stackup and impedance workbook
    moka_stackup_import    - validate and import workbook sections
*/

_msi_version = "1.0"
_msi_form = nil
_msi_busy = nil
_msi_status = "\277\325\317\320"
_msi_import_stackup = t
_msi_import_impedance = t

axlCmdRegister("moka_stackup_impedance" 'msi_ui_open ?cmdType "general")
axlCmdRegister("moka_stackup_export" 'msi_export_cmd ?cmdType "general")
axlCmdRegister("moka_stackup_import" 'msi_import_cmd ?cmdType "general")

defun( msi_install_dir ()
    axlOSSlash(axlGetVariable("MOKA_INSTALL_DIR") || "D:/Moka_Skill")
)

defun( msi_bridge_file ()
    strcat(msi_install_dir() "/MokaStackupBridge.exe")
)

defun( msi_set_status (message)
    _msi_status = message
    when(_msi_form
        errset(axlFormSetField(_msi_form "status" message) nil)
    )
    axlMsgPut(sprintf(nil "Moka skill - \265\376\262\343\057\327\350\277\271: %s" message))
    message
)

defun( msi_default_workbook_name ()
    let((design parts base)
        design = axlCurrentDesign()
        parts = axlDMFileParts(design)
        base = if(parts && nth(1 parts) then nth(1 parts) else "design")
        sprintf(nil "%s_stackup_impedance.xml" base)
    )
)

defun( msi_temp_paths ()
    let((base)
        base = axlTempFile(t)
        list(base strcat(base ".tcf") strcat(base "_patched.tcf") strcat(base ".log"))
    )
)

defun( msi_cleanup_paths (paths)
    foreach(path paths
        when(path && isFile(path)
            errset(axlTempFileRemove(path) nil)
        )
    )
)

defun( msi_read_first_line (file_name)
    let((port line result)
        result = ""
        when(file_name && isFile(file_name)
            port = infile(file_name)
            when(port
                when(gets(line port)
                    result = buildString(parseString(line "\r\n") " ")
                )
                close(port)
            )
        )
        result
    )
)

defun( msi_exported_workbook_path (log_file requested_file)
    let((line parts actual)
        line = msi_read_first_line(log_file)
        parts = parseString(line "|")
        actual = requested_file
        when(parts && equal(car(parts) "OK") && length(parts) > 1
            actual = nth(1 parts)
        )
        if(actual && isFile(actual) then actual else nil)
    )
)

defun( msi_export_native_tcf (tcf_file log_file)
    let((format result)
        format = sprintf(
            nil
            "techfile -w -i xpe %%s \"%s\""
            axlOSBackSlash(tcf_file)
        )
        result = errset(
            axlRunBatchDBProgram(
                "techfile"
                format
                ?logfile log_file
                ?startMsg "\325\375\324\332\265\274\263\366\265\376\262\343\272\315\316\357\300\355\324\274\312\370"
                ?noProgress t
                ?silent t
            )
            nil
        )
        result && car(result) == t && isFile(tcf_file)
    )
)

defun( msi_import_native_tcf (tcf_file log_file)
    let((format result)
        when(_msi_form
            errset(axlFormClose(_msi_form) nil)
            _msi_form = nil
        )
        format = sprintf(
            nil
            "techfile -r -q -d \"%s\" %%s"
            axlOSBackSlash(tcf_file)
        )
        result = errset(
            axlRunBatchDBProgram(
                "techfile"
                format
                ?logfile log_file
                ?startMsg "\325\375\324\332\323\246\323\303\265\376\262\343\272\315\327\350\277\271\304\243\260\345"
                ?reloadDB t
                ?noProgress t
                ?silent t
            )
            nil
        )
        result && car(result) == t
    )
)

defun( msi_run_bridge_export (source_tcf workbook log_file)
    let((bridge command result actual)
        bridge = msi_bridge_file()
        if(!isFile(bridge) then
            msi_set_status("\310\261\311\331\040\115\157\153\141\123\164\141\143\153\165\160\102\162\151\144\147\145\056\145\170\145\243\254\307\353\326\330\320\302\260\262\327\260\040\115\157\153\141\040\123\153\151\154\154\241\243")
            nil
        else
            command = sprintf(
                nil
                "cmd /d /c \"\"%s\" export \"%s\" \"%s\" \"%s\"\""
                axlOSBackSlash(bridge)
                axlOSBackSlash(source_tcf)
                axlOSBackSlash(workbook)
                axlOSBackSlash(log_file)
            )
            result = errset(system(command) nil)
            if(result && numberp(car(result)) && car(result) == 0 then
                actual = msi_exported_workbook_path(log_file workbook)
                actual
            else
                nil
            )
        )
    )
)

defun( msi_run_bridge_import (
    workbook source_tcf output_tcf replace_stackup replace_impedance log_file)
    let((bridge command result)
        bridge = msi_bridge_file()
        if(!isFile(bridge) then
            msi_set_status("\310\261\311\331\040\115\157\153\141\123\164\141\143\153\165\160\102\162\151\144\147\145\056\145\170\145\243\254\307\353\326\330\320\302\260\262\327\260\040\115\157\153\141\040\123\153\151\154\154\241\243")
            nil
        else
            command = sprintf(
                nil
                "cmd /d /c \"\"%s\" import \"%s\" \"%s\" \"%s\" %s %s \"%s\"\""
                axlOSBackSlash(bridge)
                axlOSBackSlash(workbook)
                axlOSBackSlash(source_tcf)
                axlOSBackSlash(output_tcf)
                if(replace_stackup then "1" else "0")
                if(replace_impedance then "1" else "0")
                axlOSBackSlash(log_file)
            )
            result = errset(system(command) nil)
            result && numberp(car(result)) && car(result) == 0 && isFile(output_tcf)
        )
    )
)

defun( msi_export_cmd ()
    let((file_name exported_file paths base source_tcf patched_tcf log_file detail)
        _msi_busy = t
        unwindProtect(
            progn(
                file_name = axlDMFileBrowse(
                    nil
                    t
                    ?defaultName msi_default_workbook_name()
                    ?title "\265\274\263\366\265\376\262\343\057\327\350\277\271\271\244\327\367\262\276"
                    ?optFilters "\115\157\153\141\040\265\376\262\343\327\350\277\271\271\244\327\367\262\276\040\050\052\056\170\155\154\051\174\052\056\170\155\154\174"
                )
                if(!file_name then
                    msi_set_status("\265\274\263\366\322\321\310\241\317\373\241\243")
                else
                    paths = msi_temp_paths()
                    base = nth(0 paths)
                    source_tcf = nth(1 paths)
                    patched_tcf = nth(2 paths)
                    log_file = nth(3 paths)
                    msi_set_status("\325\375\324\332\265\274\263\366\265\261\307\260\265\376\262\343\272\315\327\350\277\271\324\274\312\370\056\056\056")
                    if(!msi_export_native_tcf(source_tcf log_file) then
                        detail = msi_read_first_line(log_file)
                        msi_set_status(strcat("\274\274\312\365\316\304\274\376\265\274\263\366\312\247\260\334\243\272" detail))
                    else
                        exported_file = msi_run_bridge_export(source_tcf file_name log_file)
                        if(exported_file then
                            if(equal(exported_file file_name) then
                                msi_set_status(sprintf(nil "\271\244\327\367\262\276\322\321\265\274\263\366\243\272\045\163" exported_file))
                            else
                                msi_set_status(sprintf(
                                    nil "\313\371\321\241\316\304\274\376\322\321\264\362\277\252\243\254\271\244\327\367\262\276\322\321\301\355\264\346\316\252\243\272\045\163" exported_file))
                            )
                        else
                            detail = msi_read_first_line(log_file)
                            msi_set_status(strcat("\271\244\327\367\262\276\311\372\263\311\312\247\260\334\243\272" detail))
                        )
                    )
                )
            )
            progn(
                when(paths msi_cleanup_paths(paths))
                _msi_busy = nil
            )
        )
    )
)

defun( msi_import_cmd ()
    let((file_name paths base source_tcf patched_tcf log_file detail confirm_text)
        _msi_busy = t
        unwindProtect(
            progn(
                if(!_msi_import_stackup && !_msi_import_impedance then
                    msi_set_status("\307\353\326\301\311\331\321\241\324\361\265\274\310\353\265\376\262\343\273\362\327\350\277\271\241\243")
                else
                    file_name = axlDMFileBrowse(
                        nil
                        nil
                        ?title "\265\274\310\353\265\376\262\343\057\327\350\277\271\271\244\327\367\262\276"
                        ?optFilters "\115\157\153\141\040\265\376\262\343\327\350\277\271\271\244\327\367\262\276\040\050\052\056\170\155\154\051\174\052\056\170\155\154\174"
                    )
                    if(!file_name then
                        msi_set_status("\265\274\310\353\322\321\310\241\317\373\241\243")
                    else
                        confirm_text = "\275\253\312\271\323\303\313\371\321\241\271\244\327\367\262\276\314\346\273\273\265\261\307\260\311\350\274\306\326\320\322\321\271\264\321\241\265\304\304\332\310\335\243\254\312\307\267\361\274\314\320\370\243\277"
                        if(!axlUIYesNo(confirm_text "Moka skill - \265\376\262\343\057\327\350\277\271" 'no) then
                            msi_set_status("\265\274\310\353\322\321\310\241\317\373\241\243")
                        else
                            paths = msi_temp_paths()
                            base = nth(0 paths)
                            source_tcf = nth(1 paths)
                            patched_tcf = nth(2 paths)
                            log_file = nth(3 paths)
                            msi_set_status("\325\375\324\332\320\243\321\351\271\244\327\367\262\276\323\353\265\261\307\260\311\350\274\306\056\056\056")
                            if(!msi_export_native_tcf(source_tcf log_file) then
                                detail = msi_read_first_line(log_file)
                                msi_set_status(strcat("\316\336\267\250\273\361\310\241\265\261\307\260\274\274\312\365\312\375\276\335\243\272" detail))
                            else
                                if(!msi_run_bridge_import(
                                    file_name source_tcf patched_tcf
                                    _msi_import_stackup _msi_import_impedance log_file)
                                then
                                    detail = msi_read_first_line(log_file)
                                    msi_set_status(strcat("\271\244\327\367\262\276\320\243\321\351\312\247\260\334\243\272" detail))
                                else
                                    msi_set_status("\325\375\324\332\323\246\323\303\322\321\320\243\321\351\265\304\274\274\312\365\304\243\260\345\056\056\056")
                                    if(msi_import_native_tcf(patched_tcf log_file) then
                                        msi_set_status("\265\376\262\343\057\327\350\277\271\304\243\260\345\323\246\323\303\263\311\271\246\241\243")
                                    else
                                        detail = msi_read_first_line(log_file)
                                        msi_set_status(strcat("\274\274\312\365\316\304\274\376\265\274\310\353\312\247\260\334\243\272" detail))
                                    )
                                )
                            )
                        )
                    )
                )
            )
            progn(
                when(paths msi_cleanup_paths(paths))
                _msi_busy = nil
            )
        )
    )
)

defun( msi_write_form (form_file)
    let((port ok)
        ok = nil
        port = outfile(form_file)
        when(port
            fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\n")
            fprintf(port "FORM\nFIXED\nPORT 82 18\n")
            fprintf(port "HEADER \"Moka skill v%s - \265\376\262\343 / \327\350\277\271\"\n" _msi_version)
            fprintf(port "TILE\n")

            fprintf(port "GROUP \"\271\244\327\367\262\276\304\243\260\345\"\nGLOC 2 1\nGSIZE 78 10\nENDGROUP\n")
            fprintf(port "TEXT \"\327\264\314\254\243\272\"\nTLOC 4 3\nENDTEXT\n")
            fprintf(port "FIELD status\nFLOC 14 3\nSTRFILLIN 62 180\nENDFIELD\n")
            fprintf(port "FIELD btn_export\nFLOC 4 6\nMENUBUTTON \"\265\274\263\366\261\355\270\361\" 18 3\nENDFIELD\n")
            fprintf(port "FIELD btn_import\nFLOC 24 6\nMENUBUTTON \"\265\274\310\353\040\057\040\314\346\273\273\" 18 3\nENDFIELD\n")
            fprintf(port "FIELD import_stackup\nFLOC 46 6\nCHECKLIST \"\314\346\273\273\265\376\262\343\"\nENDFIELD\n")
            fprintf(port "FIELD import_impedance\nFLOC 62 6\nCHECKLIST \"\314\346\273\273\327\350\277\271\"\nENDFIELD\n")

            fprintf(port "FIELD btn_close\nFLOC 66 13\nMENUBUTTON \"\271\330\261\325\" 10 3\nENDFIELD\n")
            fprintf(port "ENDTILE\nENDFORM\n")
            close(port)
            ok = t
        )
        ok
    )
)

defun( msi_form_cb (form)
    let((field)
        if(form->doneState > 0 then
            _msi_form = nil
        else
            field = form->curField
            case(field
                ("btn_export"
                    if(_msi_busy then
                        msi_set_status("\322\321\323\320\265\376\262\343\262\331\327\367\325\375\324\332\324\313\320\320\241\243")
                    else
                        _msi_busy = t
                        axlShellPost("moka_stackup_export")
                    )
                )
                ("btn_import"
                    if(_msi_busy then
                        msi_set_status("\322\321\323\320\265\376\262\343\262\331\327\367\325\375\324\332\324\313\320\320\241\243")
                    else
                        _msi_import_stackup = axlFormGetField(form "import_stackup")
                        _msi_import_impedance = axlFormGetField(form "import_impedance")
                        _msi_busy = t
                        axlShellPost("moka_stackup_import")
                    )
                )
                ("import_stackup"
                    _msi_import_stackup = axlFormGetField(form "import_stackup")
                )
                ("import_impedance"
                    _msi_import_impedance = axlFormGetField(form "import_impedance")
                )
                ("btn_close"
                    _msi_form = nil
                    errset(axlFormClose(form) nil)
                )
            )
        )
        t
    )
)

defun( msi_ui_open ()
    let((form_file form)
        if(_msi_form then
            errset(axlFormDisplay(_msi_form) nil)
        else
            form_file = axlTempFile(t)
            if(msi_write_form(form_file) then
                form = axlFormCreate((gensym) form_file nil 'msi_form_cb t)
                when(isFile(form_file) errset(axlTempFileRemove(form_file) nil))
                if(form then
                    _msi_form = form
                    errset(axlFormSetFieldEditable(form "status" nil) nil)
                    axlFormSetField(form "status" _msi_status)
                    axlFormSetField(form "import_stackup" _msi_import_stackup)
                    axlFormSetField(form "import_impedance" _msi_import_impedance)
                    axlFormDisplay(form)
                else
                    msi_set_status("\316\336\267\250\264\264\275\250\265\376\262\343\057\327\350\277\271\303\346\260\345\241\243")
                )
            else
                msi_set_status("\316\336\267\250\320\264\310\353\265\376\262\343\057\327\350\277\271\261\355\265\245\266\250\322\345\241\243")
            )
        )
        _msi_form
    )
)
