# Cosmo Communicator: Plasma session environment (startplasma sources
# $XDG_CONFIG_DIRS/plasma-workspace/env/*.sh before starting KWin).
# AFBC off, as the Gemini: panfrost cannot CPU-map AFBC textures, so Qt's
# partial uploads become many tiny GPU jobs. The Gemini's KWin safety
# margin is for its copy-to-screen display driver and is not needed here
# (mediatek-drm page flips).
export PAN_MESA_DEBUG=noafbc
