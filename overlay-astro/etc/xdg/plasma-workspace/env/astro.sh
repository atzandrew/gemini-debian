# Astro Slide: Plasma session environment (startplasma sources
# $XDG_CONFIG_DIRS/plasma-workspace/env/*.sh before starting KWin), as
# overlay-cosmo's cosmo.sh. Measured in astro-linux618 docs/frame-pacing.md:
# - KWin on OpenGL ES: with the default desktop GL 3.1 core context on
#   panfrost (Mali-G57), KWin raised thousands of GL_INVALID_OPERATION per
#   second (no vertex array bound) on full repaints of the rotated output,
#   also on Mesa 26.1.6; on GLES 3.1: none.
# - AFBC off, as the Cosmo/Gemini: panfrost cannot CPU-map AFBC textures,
#   so Qt's partial uploads become many tiny GPU jobs (plasmashell: 2536
#   jobs, 188 ms queue wait in a start-menu run -> 164 jobs, 0.26 ms).
export KWIN_COMPOSE=O2ES
export PAN_MESA_DEBUG=noafbc
