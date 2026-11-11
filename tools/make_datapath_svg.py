#!/usr/bin/env python3
"""
make_datapath_svg.py - draw the single-cycle datapath as an SVG.

Generated rather than hand-drawn so the diagram can be regenerated when the
design changes. Writes docs/datapath.svg.
"""

W, H = 1480, 940
P = []          # svg fragments


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def box(x, y, w, h, title, sub=None, cls="unit"):
    P.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="6"/>')
    ty = y + h / 2 + (0 if sub is None else -6)
    P.append(f'<text class="t-title" x="{x+w/2}" y="{ty}">{esc(title)}</text>')
    if sub:
        P.append(f'<text class="t-sub" x="{x+w/2}" y="{ty+16}">{esc(sub)}</text>')
    return dict(x=x, y=y, w=w, h=h)


def mux(x, y, h, label=None, w=22):
    """A trapezoidal 2:1 / 3:1 mux, narrow at the output side."""
    P.append(f'<path class="mux" d="M{x},{y} L{x+w},{y+10} L{x+w},{y+h-10} '
             f'L{x},{y+h} Z"/>')
    if label:
        P.append(f'<text class="t-mux" x="{x+w/2}" y="{y+h/2+4}">{esc(label)}</text>')
    return dict(x=x, y=y, w=w, h=h)


def alu(x, y, w, h):
    """Classic notched-arrow ALU shape."""
    n = 16
    P.append(f'<path class="unit" d="M{x},{y} L{x+w},{y+h*0.28} L{x+w},{y+h*0.72} '
             f'L{x},{y+h} L{x},{y+h/2+n/2} L{x+14},{y+h/2} L{x},{y+h/2-n/2} Z"/>')
    P.append(f'<text class="t-title" x="{x+w*0.52}" y="{y+h/2+5}">ALU</text>')
    return dict(x=x, y=y, w=w, h=h)


def wire(points, label=None, lx=None, ly=None, cls="w", arrow=True, anchor="middle"):
    d = " ".join(f"{px},{py}" for px, py in points)
    marker = ' marker-end="url(#a)"' if arrow else ""
    P.append(f'<polyline class="{cls}" points="{d}"{marker}/>')
    if label:
        x, y = (lx, ly) if lx is not None else points[0]
        P.append(f'<text class="t-wire" x="{x}" y="{y}" text-anchor="{anchor}">'
                 f'{esc(label)}</text>')


def ctrl(points, label=None, lx=None, ly=None, anchor="middle", arrow=True):
    wire(points, label, lx, ly, cls="c", arrow=arrow, anchor=anchor)


def dot(x, y):
    P.append(f'<circle class="dot" cx="{x}" cy="{y}" r="4"/>')


def note(x, y, text, anchor="start", cls="t-note"):
    P.append(f'<text class="{cls}" x="{x}" y="{y}" text-anchor="{anchor}">'
             f'{esc(text)}</text>')


# ============================================================== the drawing ===
note(40, 42, "Single-Cycle RV32I Datapath", cls="t-h1")

# ---- next-PC mux, the PC, and the +4 adder ---------------------------------
pcmux = mux(60, 300, 120, "3:1")
pcreg = box(120, 320, 70, 80, "PC", "register")
imem  = box(240, 310, 120, 100, "Instruction", "memory")
add4  = box(250, 180, 70, 50, "+4", None, "unit small")

wire([(pcmux["x"] + pcmux["w"], 360), (pcreg["x"], 360)])
wire([(pcreg["x"] + pcreg["w"], 360), (imem["x"], 360)], "PC", 215, 350)
dot(210, 360)

# PC up into the +4 adder, and the PC+4 result back round to the mux
wire([(210, 360), (210, 205), (add4["x"], 205)])
wire([(add4["x"] + add4["w"], 205), (505, 205)], arrow=False)
wire([(505, 205), (505, 148), (40, 148), (40, 318), (pcmux["x"], 318)],
     "PC+4", 240, 141)
dot(505, 205)

# ---- instruction fields ------------------------------------------------------
note(372, 300, "instruction [31:0]", cls="t-note")
wire([(imem["x"] + imem["w"], 360), (400, 360)], arrow=False)
dot(400, 360)

rf   = box(470, 300, 150, 170, "Register file", "32 x 32-bit,  x0 = 0")
immg = box(470, 540, 150, 60, "Immediate", "generator")

for ylvl, lbl, tgt in ((330, "rs1 [19:15]", rf["y"] + 30),
                       (360, "rs2 [24:20]", rf["y"] + 70),
                       (390, "rd  [11:7]",  rf["y"] + 140)):
    wire([(400, 360), (400, ylvl), (432, ylvl), (432, tgt), (rf["x"], tgt)],
         lbl, 428, ylvl - 6, anchor="end")
wire([(400, 360), (400, 570), (immg["x"], 570)], "instr [31:7]", 436, 562)

# ---- control -------------------------------------------------------------------
cu   = box(700, 95, 300, 72, "Control unit", "opcode -> control signals", "ctrlbox")
aluc = box(1040, 95, 170, 72, "ALU control", "funct3 / funct7", "ctrlbox")
ctrl([(400, 360), (400, 131), (cu["x"], 131)], "opcode [6:0]", 550, 124)
ctrl([(cu["x"] + cu["w"], 131), (aluc["x"], 131)], "ALUOp", 1020, 124)
ctrl([(412, 360), (412, 176), (1120, 176), (1120, aluc["y"] + aluc["h"])])
note(424, 200, "funct3 [14:12],  instr[30]", cls="t-note")

# ---- operand muxes and ALU -------------------------------------------------------
muxa = mux(660, 300, 80, "3:1")
muxb = mux(660, 400, 80, "2:1")
a    = alu(730, 290, 110, 190)
wire([(rf["x"] + rf["w"], 332), (muxa["x"], 332)], "rs1", 638, 325)
wire([(rf["x"] + rf["w"], 430), (muxb["x"], 430)], "rs2", 638, 423)
# PC as the second operand-A source (auipc)
wire([(210, 240), (652, 240), (652, 348), (muxa["x"], 348)], "PC", 330, 233)
note(638, 368, "0", anchor="end", cls="t-wire")
wire([(644, 364), (muxa["x"], 364)])
dot(210, 240)
# the immediate as the second operand-B source
wire([(immg["x"] + immg["w"], 570), (643, 570), (643, 450), (muxb["x"], 450)],
     "imm", 666, 556)
dot(643, 570)

wire([(muxa["x"] + muxa["w"], 340), (a["x"], 340)])
wire([(muxb["x"] + muxb["w"], 440), (a["x"], 440)])
ctrl([(cu["x"] + 40, cu["y"] + cu["h"]), (cu["x"] + 40, 252), (672, 252),
      (672, 300)], "ALUSrcA / ALUSrcB", 728, 245)
ctrl([(aluc["x"] + 85, aluc["y"] + aluc["h"]), (aluc["x"] + 85, 228),
      (800, 228), (800, 290)], "alu_ctrl", 880, 221)

# ---- branch comparator -------------------------------------------------------------
bu = box(730, 640, 150, 60, "Branch unit", "comparator")
dot(635, 430)
dot(648, 430)
wire([(635, 332), (635, 660), (bu["x"], 660)])
dot(635, 332)
wire([(648, 430), (648, 685), (bu["x"], 685)])
note(660, 712, "rs1, rs2", cls="t-note")

# ---- PC-target adder ------------------------------------------------------------------
tadd = box(300, 700, 90, 55, "+", "PC + imm", "unit small")
wire([(210, 360), (210, 727), (tadd["x"], 727)])
wire([(643, 570), (643, 800), (262, 800), (262, 742), (tadd["x"], 742)])
wire([(tadd["x"] + tadd["w"], 727), (430, 727), (430, 845), (30, 845),
      (30, 352), (pcmux["x"], 352)], "branch / jal target", 700, 838)

# ---- memory stage ------------------------------------------------------------------------
lsu  = box(900, 300, 110, 190, "Load /", "store unit")
dmem = box(1060, 320, 120, 150, "Data", "memory")

wire([(a["x"] + a["w"], 385), (lsu["x"], 385)], "address", 870, 378)
dot(870, 385)
wire([(635, 430), (635, 525), (880, 525), (880, 455), (lsu["x"], 455)],
     "rs2 (store data)", 760, 543)
wire([(lsu["x"] + lsu["w"], 355), (dmem["x"], 355)], "wdata, wstrb", 1035, 345)
wire([(dmem["x"], 435), (lsu["x"] + lsu["w"], 435)], "rdata", 1035, 455)
ctrl([(cu["x"] + 200, cu["y"] + cu["h"]), (cu["x"] + 200, 214), (952, 214),
      (952, 300)], "MemWrite", 982, 207)

# ---- write-back mux -----------------------------------------------------------------------
wbmux = mux(1250, 300, 120, "3:1")
wire([(870, 385), (870, 268), (1232, 268), (1232, 315), (wbmux["x"], 315)],
     "ALU result", 1060, 261)
# the loaded value leaves the LSU underneath the data memory, not through it
wire([(955, lsu["y"] + lsu["h"]), (955, 560), (1262, 560), (1262, 430),
      (wbmux["x"] + 10, 430)], "load data", 1110, 576)
wire([(505, 205), (505, 84), (1240, 84), (1240, 355), (wbmux["x"], 355)],
     "PC+4 (return address)", 620, 77)
ctrl([(cu["x"] + 150, cu["y"] + cu["h"]), (cu["x"] + 150, 190), (1300, 190),
      (1300, 300)], "ResultSrc", 1360, 183)

# write-back path back to the register file
wire([(wbmux["x"] + wbmux["w"], 360), (1420, 360), (1420, 890), (452, 890),
      (452, 455), (rf["x"], 455)], "write-back to rd", 980, 883)
ctrl([(cu["x"] + 260, cu["y"] + cu["h"]), (cu["x"] + 260, 284), (545, 284),
      (545, rf["y"])], "RegWrite", 560, 277)

# ---- next-PC selection ------------------------------------------------------------------------
wire([(a["x"] + a["w"], 460), (862, 460), (862, 618), (20, 618), (20, 384),
      (pcmux["x"], 384)], "jalr target  (ALU result, bit 0 cleared)", 300, 611)
ctrl([(bu["x"] + bu["w"], 670), (1446, 670), (1446, 920), (95, 920),
      (95, pcmux["y"] + pcmux["h"])], "taken", 1410, 662)
ctrl([(cu["x"], cu["y"] + 50), (676, 145), (676, 56), (110, 56), (110, 300)],
     "branch / jump / jalr", 480, 49)

# ---- legend -------------------------------------------------------------------------------------
note(470, 646, "solid = data", cls="t-note b")
note(470, 662, "dashed = control")
note(470, 686, "Inside one clock period:", cls="t-note b")
for i, sline in enumerate(["1  fetch", "2  decode", "3  execute",
                           "4  memory", "5  write-back"]):
    note(470, 702 + i * 15, sline, cls="t-note")

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif">
<defs>
  <marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
    <path d="M0,1 L9,5 L0,9 z" fill="#334155"/>
  </marker>
</defs>
<style>
  rect.unit, path.unit {{ fill:#f8fafc; stroke:#334155; stroke-width:1.8; }}
  rect.small {{ fill:#f1f5f9; }}
  rect.ctrlbox {{ fill:#eef2ff; stroke:#4338ca; stroke-width:1.8; }}
  path.mux {{ fill:#e2e8f0; stroke:#334155; stroke-width:1.5; }}
  polyline.w {{ fill:none; stroke:#334155; stroke-width:1.8; }}
  polyline.c {{ fill:none; stroke:#4338ca; stroke-width:1.5; stroke-dasharray:6 4; }}
  circle.dot {{ fill:#334155; }}
  text {{ fill:#0f172a; }}
  text.t-title {{ font-size:15px; font-weight:600; text-anchor:middle; }}
  text.t-sub {{ font-size:11px; fill:#475569; text-anchor:middle; }}
  text.t-mux {{ font-size:10px; fill:#334155; text-anchor:middle; }}
  text.t-wire {{ font-size:11.5px; fill:#334155; }}
  text.t-note {{ font-size:11.5px; fill:#475569; }}
  text.b {{ font-weight:700; fill:#0f172a; }}
  text.t-h1 {{ font-size:22px; font-weight:700; }}
  text.t-h2 {{ font-size:12.5px; fill:#64748b; }}
</style>
{chr(10).join(P)}
</svg>
'''

with open("docs/datapath.svg", "w") as f:
    f.write(svg)
print("docs/datapath.svg written")
