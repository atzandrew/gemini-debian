# Gemini PDA: the two display variables from /etc/environment, also set by
# startplasma itself (it sources $XDG_CONFIG_DIRS/plasma-workspace/env/*.sh
# before starting KWin). /etc/environment only reaches the session through
# PAM's pam_env, and the login manager's PAM stack decides whether that runs;
# this way KWin gets them whichever login manager started Plasma.
# Reasons: see /etc/environment.
export PAN_MESA_DEBUG=noafbc
export KWIN_DRM_OVERRIDE_SAFETY_MARGIN=12000
