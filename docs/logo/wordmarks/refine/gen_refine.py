from fontTools.ttLib import TTCollection
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.svgPathPen import SVGPathPen
import pathops
f=[f for f in TTCollection('/System/Library/Fonts/Avenir Next.ttc').fonts if f['name'].getDebugName(4)=='Avenir Next Heavy'][0]
gs=f.getGlyphSet(); cm=f.getBestCmap()
S=120/708; BASE=188
def glyph(c,x):
    p=pathops.Path(); gs[cm[ord(c)]].draw(TransformPen(p.getPen(),(1,0,0,1,x,0))); return p
def poly(pts):
    p=pathops.Path(); pen=p.getPen(); pen.moveTo(pts[0]); [pen.lineTo(q) for q in pts[1:]]; pen.closePath(); return p
def rrect(x,y,w,h,r):
    k=0.5523*r; p=pathops.Path(); pen=p.getPen()
    pen.moveTo((x+r,y)); pen.lineTo((x+w-r,y)); pen.curveTo((x+w-r+k,y),(x+w,y+r-k),(x+w,y+r))
    pen.lineTo((x+w,y+h-r)); pen.curveTo((x+w,y+h-r+k),(x+w-r+k,y+h),(x+w-r,y+h))
    pen.lineTo((x+r,y+h)); pen.curveTo((x+r-k,y+h),(x,y+h-r+k),(x,y+h-r))
    pen.lineTo((x,y+r)); pen.curveTo((x,y+r-k),(x+r-k,y),(x+r,y)); pen.closePath(); return p
def U(*ps):
    out=ps[0]
    for q in ps[1:]: out=pathops.op(out,q,pathops.PathOp.UNION)
    return out
def D(a,b): return pathops.op(a,b,pathops.PathOp.DIFFERENCE)
def save(name,path,title):
    xs=path.bounds; pad=0
    pen=SVGPathPen(None); path.draw(TransformPen(pen,(S,0,0,-S,-xs[0]*S,BASE)))
    w=(xs[2]-xs[0])*S
    open(f'{name}.svg','w').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.2f} 256"><title>{title}</title><path d="{pen.getCommands()}"/></svg>\n')
    print(name, round(w,1))
# optical spacing (font units): A-S tight, S-M slightly tighter than default
xS=776+24; xM=xS+617+4
A=glyph('A',0); Sg=glyph('S',xS); M=glyph('M',xM)
save('asm-c1-tuned',U(A,Sg,M),'ASM wordmark — Avenir Next Heavy, tuned spacing')
# Key A: remove crossbar (Λ), drop a square key on the baseline
lam=D(A,poly([(236,0),(386,461),(533,0)]))
key=rrect(320,0,130,130,20)
save('asm-c2-key',U(lam,key,Sg,M),'ASM wordmark — Key A')
save('a-key-symbol-raw',U(lam,key),'A key symbol')
# C3 Button A: crossbar becomes a key that cuts through both legs (knock-out gap)
def button_A(kx,ky,kw,kh,r,g):
    base=D(A,poly([(236,0),(386,461),(533,0)]))
    base=D(base,rrect(kx-g,ky-g,kw+2*g,kh+2*g,r+g))
    return U(base,rrect(kx,ky,kw,kh,r))
bA=button_A(262,92,246,150,26,30)
save('asm-c3-button',U(bA,Sg,M),'ASM wordmark — Button A')
save('a-button-symbol-raw',bA,'A button symbol')
