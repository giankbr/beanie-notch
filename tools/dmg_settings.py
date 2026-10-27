# dmgbuild settings: Beanie and an Applications link over the drawn background (tools/make_dmg_background.swift).
import os

app = defines['app']
format = 'UDZO'
files = [app]
symlinks = {'Applications': '/Applications'}
background = defines['background']
icon_size = 112
text_size = 13
icon_locations = {os.path.basename(app): (170, 200), 'Applications': (470, 200)}
# The frame includes the title bar, so it's a little taller than the 640×400 background.
window_rect = ((240, 160), (640, 428))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
