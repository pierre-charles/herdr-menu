# Draws Remora's icons as SVG, then renders the PNGs the app and README use (with render.swift):
#   icon/remora.svg, icon/remora.png     the app icon, 1024px
#   icon/menubar.svg, icon/menubar.png   the menu bar silhouette, a template image (the app adds the badge)
#   screenshots/badge-*.png              the README's badge table
# Run from the repo root after changing anything here: python3 icon/make.py
import subprocess

GRADIENT = ["#38bdf8", "#1e3a8a", "#0b1030"]  # deep sea, top right to bottom left
SCALE = 0.85  # the fish's share of the tile, padding all round

# The fish, facing right, drawn in a 1024 box around (540, 515): a chubby body whose top has the suction disc's
# ridges as soft bumps, a forked tail, and an underbite smile
DISC = "Q480,336 490,334 " + " ".join(f"Q{x+27},292 {x+54},334" for x in range(490, 760, 54)) + " Q775,336 780,354"
BODY = f"M292,575 C292,460 370,372 462,352 {DISC} C840,360 905,430 905,532 L930,572 C912,650 820,730 640,736 C450,742 300,680 292,575 Z"
TAIL = ("M300,575 C250,525 200,470 168,452 C150,450 144,470 150,490 C162,530 182,560 200,580 "
        "C182,600 162,630 150,670 C144,690 150,710 168,708 C200,690 250,635 300,605 Z")
GROOVES = "".join(f'<line x1="{x}" y1="336" x2="{x}" y2="362"/>' for x in range(544, 760, 54))
SMILE = "M930,574 C890,606 822,606 784,574 C828,626 900,622 928,590 Z"
FIN = "M590,620 C640,640 660,690 640,725 C595,712 572,670 578,630 Z"

def app_icon():
    a, b, c = GRADIENT
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<defs>
<linearGradient id="bg" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{a}"/><stop offset="0.5" stop-color="{b}"/><stop offset="1" stop-color="{c}"/></linearGradient>
<linearGradient id="glass" x1="0.6" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="0.55" stop-color="#eef2ff"/><stop offset="1" stop-color="#cfd2ff"/></linearGradient>
<radialGradient id="shade" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#140f45" stop-opacity="0.35"/><stop offset="1" stop-color="#140f45" stop-opacity="0"/></radialGradient>
</defs>
<rect x="100" y="100" width="824" height="824" rx="190" fill="url(#bg)"/>
<g transform="translate(512,512) scale({SCALE}) translate(-540,-515)">
<ellipse cx="560" cy="730" rx="330" ry="70" fill="url(#shade)"/>
<path d="{TAIL}" fill="url(#glass)" opacity="0.92"/>
<path d="{BODY}" fill="url(#glass)" opacity="0.96"/>
<g stroke="#b9bff2" stroke-width="7" stroke-linecap="round">{GROOVES}</g>
<path d="{FIN}" fill="#d9dcff"/>
<ellipse cx="740" cy="478" rx="40" ry="50" fill="#2a1f6e"/><ellipse cx="752" cy="462" rx="11" ry="13" fill="#fff" opacity="0.9"/>
<path d="{SMILE}" fill="#2a1f6e"/>
</g></svg>'''

# One colour with the eye and smile cut out, a bigger eye so it survives at menu bar size, cropped to the fish
def silhouette(color="#000", id="m"):
    return f'''<mask id="{id}"><rect x="0" y="0" width="1100" height="1100" fill="#fff"/>
<ellipse cx="740" cy="478" rx="50" ry="60" fill="#000"/><path d="{SMILE}" fill="#000" transform="translate(-8,-4)"/></mask>
<g mask="url(#{id})" fill="{color}"><path d="{TAIL}"/><path d="{BODY}"/></g>'''

MENUBAR_BOX = (140, 285, 800, 460)  # x, y, width, height around the fish

def menubar():
    x, y, w, h = MENUBAR_BOX
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x} {y} {w} {h}">{silhouette()}</svg>'

# A README badge: the white silhouette on a dark menu bar tile, with the app's notch and dot over the tail when there's a status
def badge(dot=None):
    x, y, w, h = MENUBAR_BOX
    s = 52 / w  # 52px wide at 2x, like the app's 26pt icon
    notch = '<circle cx="175" cy="700" r="120" fill="#000"/>' if dot else ""
    cut = silhouette("#f5f5f7").replace('<path d="M930', notch + '<path d="M930', 1)
    dots = f'<circle cx="175" cy="700" r="76" fill="{dot}"/>' if dot else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 88 56"><rect width="88" height="56" rx="10" fill="#1e1e1e"/>
<g transform="translate(18,13) scale({s}) translate({-x},{-y})">{cut}{dots}</g></svg>'''

files = {
    "icon/remora.svg": (app_icon(), "icon/remora.png", 1024, 1024),
    "icon/menubar.svg": (menubar(), "icon/menubar.png", 340, 196),
    "icon/badge-none.svg": (badge(), "screenshots/badge-none.png", 88, 56),
    "icon/badge-blocked.svg": (badge("#f38ba8"), "screenshots/badge-blocked.png", 88, 56),
    "icon/badge-done.svg": (badge("#94e2d5"), "screenshots/badge-done.png", 88, 56),
}
args = []
for svg, (text, png, w, h) in files.items():
    open(svg, "w").write(text)
    args += [svg, png, str(w), str(h)]
subprocess.run(["swift", "icon/render.swift", *args], check=True)
