class_name HudLayout
extends RefCounted
## The HUD's geometry and palette in one place (scripts/hud.gd and scripts/hud/*).
##
## The top-centre column is a stack, and everything in it has to stay clear of the row above:
##   match clock        CLOCK_TOP .. CLOCK_BOTTOM      (36 px digits, drawn by scenes/hud.tscn)
##   standing / CTF     STANDING_TOP .. STANDING_BOTTOM (one line, FFA place or the CTF line)
##   CTF status block   CTF_TOP .. CTF_TOP + CTF_HEIGHT (three 14 px lines, only while CTF runs)
##   streak/flag popup  POPUP_TOP .. POPUP_TOP + POPUP_HEIGHT
## The clock lives in the scene, so its numbers are repeated there; `tools/check_hud_column` reads the
## .tscn and fails when the two drift apart or when the stack starts to overlap.
##
## Colours: one accent for everything selected or held (held weapon, selected streak, own scoreboard
## row, trick tags) instead of a handful of near-identical golds. Configurable HUD colours (crosshair,
## colourblind teams) stay on `Game`.

# --- Top-centre column -------------------------------------------------------
const CLOCK_TOP := 20.0
const CLOCK_BOTTOM := 60.0
const CLOCK_FONT := 36
const STANDING_TOP := 64.0
const STANDING_BOTTOM := 86.0
const STANDING_HEIGHT := STANDING_BOTTOM - STANDING_TOP
const STANDING_FONT := 16
const CTF_LINE_FONT := 14 # the CTF line is three rows of 14 px text at the same spot
const CTF_TOP := 72.0 # a clear gap under the match clock (#160)
const CTF_HEIGHT := 60.0 # three 14 px lines
const POPUP_TOP := 92.0 # streak/flag popup: clear of the clock and the standing line
const POPUP_HEIGHT := 70.0
const POPUP_GAP := 8.0 # clearance between the CTF status block and the popup that follows it

# --- Palette -----------------------------------------------------------------
# The crystal palette (docs/ui-crystal/HANDOFF.md): smoke glass, pale shell, ice seams. Gold stays
# only for rewards (TRICK, friendly popups).
const ACCENT := CrystalStyle.ICE # ice: held weapon seam, ready streak, own row, standing
const PANEL := Color(0.059, 0.078, 0.106, 0.78) # smoke glass behind a scoreboard/streak block
const SLOT_IDLE := CrystalStyle.SMOKE
const SLOT_ON := CrystalStyle.SHELL # the held weapon is the pale shell
const SLOT_TEXT_ON := Color(0.07, 0.08, 0.10) # dark text on the pale shell
const POPUP_FRIENDLY := Color(1.0, 0.86, 0.4)
const POPUP_HOSTILE := Color(1.0, 0.36, 0.3)
const TRICK := Color(1.0, 0.78, 0.22) # trickshot gold: popup, feed tag, killcam, style king

# --- Damage direction wedge (around the crosshair) ----------------------------
const DMG_LIFE := 1.3 # seconds a wedge stays, fading out
const DMG_MAX := 6 # wedges kept; older ones are dropped
const DMG_RADIUS := 118.0 # px from the screen centre to the wedge
const DMG_HALF := 0.36 # rad, half the wedge's arc (~20°)
