/* Standalone loader and localized menu registration smoke test. */

defun( axlGetVariable (name)
    if(equal(name "MTS_INSTALL_DIR") then getWorkingDir() else nil)
)

defun( axlSetVariable (name value) t)
defun( axlOSSlash (path) path)
defun( axlMsgPut (message) printf("%s\n" message))
defvar(_mts_test_menu nil)

defun( axlUIMenuRegister (location menu_items)
    _mts_test_menu = menu_items
    t
)

load("mooretronics_symbols_loader.il")

unless(_mts_menu_registered && _mts_test_menu && length(_mts_test_menu) == 3
    error("Localized Allegro menu registration failed.")
)

unless(strlen(cadr(car(_mts_test_menu))) == 21
    error("Localized top-level menu text was not encoded as CP936.")
)

printf("MTS_LOADER_MENU_OK items=%d\n" length(_mts_test_menu))
exit()
