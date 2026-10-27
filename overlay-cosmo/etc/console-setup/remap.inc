# Appended to the console keymap by ckbcomp (console-setup).
#
# Cosmo: Ctrl+Fn+Alt+Backspace = Ctrl+Alt+Delete. Fn is AltGr on the console
# (cosmo xkb layout, Fn = ISO_Level3_Shift) and Fn+Backspace is Delete, but
# the kernel's reboot request (keysym Boot) is only bound to the real Delete
# keys. Bind it on Backspace (keycode 14) with AltGr+Control+Alt, for every
# modifier variant ckbcomp uses (shiftl/shiftr for groups, ctrll for the
# CapsLock fix). systemd turns the request into ctrl-alt-del.target, a
# clean reboot; seven presses within 2 s force it.
altgr control alt keycode 14 = Boot
shiftl altgr control alt keycode 14 = Boot
shiftr altgr control alt keycode 14 = Boot
shiftr shiftl altgr control alt keycode 14 = Boot
ctrll altgr control alt keycode 14 = Boot
ctrll shiftl altgr control alt keycode 14 = Boot
ctrll shiftr altgr control alt keycode 14 = Boot
ctrll shiftr shiftl altgr control alt keycode 14 = Boot
