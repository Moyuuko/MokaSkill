/* Standalone compatibility loader for Moka skill - PCB 标识放置 v1.0. */

defvar(_mts_menu_registered nil)

let((install_dir main_file)
    install_dir = axlGetVariable("MTS_INSTALL_DIR")
    if(!stringp(install_dir) || strlen(install_dir) == 0 then
        install_dir = getWorkingDir()
    )
    install_dir = axlOSSlash(install_dir)
    axlSetVariable("MTS_INSTALL_DIR" install_dir)
    setSkillPath(cons(install_dir getSkillPath()))

    main_file = strcat(install_dir "/mooretronics_symbols.il")
    if(isFile(main_file) then
        load(main_file)
    else
        axlMsgPut(sprintf(nil "Mooretronics Symbols: file not found: %s" main_file))
    )
)

defun( mts_register_menu ()
    let((menu_items result)
        menu_items = list(
            list('popup mts_text(list(77 111 111 114 101 116 114 111 110 105 99 115 32 183 251 186 197 40 38 77 41)))
            list(mts_text(list(180 242 191 170 183 251 186 197 195 230 176 229 40 38 79 41 46 46 46)) "mts_symbols")
            list(mts_text(list(176 180 181 177 199 176 201 232 214 195 183 197 214 195 40 38 80 41)) "mts_place")
        )
        when(!_mts_menu_registered && isCallable('axlUIMenuRegister)
            result = errset(axlUIMenuRegister(-1 menu_items) t)
            when(result && car(result) _mts_menu_registered = t)
        )
    )
)

errset(mts_register_menu() t)
