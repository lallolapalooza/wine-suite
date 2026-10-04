No Notepad++-exclusive patches are needed.

Notepad++ is a pure Win32 application: it only uses the generic, undocumented
dark-mode API set (uxtheme ordinals 133/135/136/137 + dwmapi
DWMWA_USE_IMMERSIVE_DARK_MODE) and the generic UAH menu-bar messages. The fix is
therefore entirely generic Win32 behaviour and lives in ../000*-*.patch, which any
dark-mode application benefits from.

If a future requirement turns out to be specific to this application (for example a
workaround for an unusual call sequence), its patch belongs in this directory.
