import pathops
from fontTools.pens.svgPathPen import SVGPathPen
def rrect(x,y,w,h,r):
    k=0.5523*r; p=pathops.Path(); pen=p.getPen()
    pen.moveTo((x+r,y)); pen.lineTo((x+w-r,y)); pen.curveTo((x+w-r+k,y),(x+w,y+r-k),(x+w,y+r))
    pen.lineTo((x+w,y+h-r)); pen.curveTo((x+w,y+h-r+k),(x+w-r+k,y+h),(x+w-r,y+h))
    pen.lineTo((x+r,y+h)); pen.curveTo((x+r-k,y+h),(x,y+h-r+k),(x,y+h-r))
    pen.lineTo((x,y+r)); pen.curveTo((x,y+r-k),(x+r-k,y),(x+r,y)); pen.closePath(); return p
def d(p): pen=SVGPathPen(None); p.draw(pen); return pen.getCommands()
A=rrect(36,36,128,128,28); B=rrect(92,92,128,128,28)
O=pathops.op(A,B,pathops.PathOp.INTERSECTION)
back=d(pathops.op(A,B,pathops.PathOp.DIFFERENCE)); front=d(pathops.op(B,A,pathops.PathOp.DIFFERENCE)); over=d(O)
PAL=[ # slug, name, back, front, overlap-colour
 ('signal','Signal — blue / coral','#3D5AFE','#FF6B57','#1B1F3B'),
 ('pulse','Pulse — violet / mint','#7B5CFF','#2EE6A8','#1E2A4A'),
 ('neon','Neon — cyan / magenta','#00B4F0','#FF2D87','#5B2BE0'),
 ('studio','Studio — ink / amber','#16181D','#FFB300','#FFFFFF'),
]
def sym(bk,fr,ov,knock):
    o='' if knock else f'<path fill="{ov}" d="{over}"/>'
    return f'<path fill="{bk}" d="{back}"/><path fill="{fr}" d="{front}"/>{o}'
for slug,name,bk,fr,ov in PAL:
    for knock in (True,False):
        n=f'double-key-{slug}-{"knockout" if knock else "overlap"}.svg'
        open(n,'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>ASM — Double Key ({name})</title>{sym(bk,fr,ov,knock)}</svg>\n')
import json; json.dump(dict(back=back,front=front,over=over,pal=PAL),open('parts.json','w'))
