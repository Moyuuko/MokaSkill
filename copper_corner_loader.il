/* Standalone loader for Copper Corner Tools. */

defvar(_cct_menu_registered nil)

let((install_dir main_file)
    install_dir = axlGetVariable("CCT_INSTALL_DIR")
    if(!stringp(install_dir) || strlen(install_dir) == 0 then
        install_dir = getWorkingDir()
    )
    install_dir = axlOSSlash(install_dir)
    axlSetVariable("CCT_INSTALL_DIR" install_dir)
    setSkillPath(cons(install_dir getSkillPath()))

    main_file = strcat(install_dir "/copper_corner_tools.il")
    if(isFile(main_file) then
        load(main_file)
    else
        axlMsgPut(sprintf(nil "Copper Corner Tools: file not found: %s" main_file))
    )
)

defun( cct_register_menu ()
    let((menu_items result)
        menu_items = list(
            list('popup "&Copper Corner Tools")
            list("&Open panel..." "copper_corner")
            list("&Apply using current settings" "copper_corner_apply")
        )
        when(!_cct_menu_registered && isCallable('axlUIMenuRegister)
            result = errset(axlUIMenuRegister(-1 menu_items) t)
            when(result && car(result) _cct_menu_registered = t)
        )
    )
)

errset(cct_register_menu() t)

