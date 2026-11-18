import sys
from fontTools.ttLib import TTFont, TTCollection
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
F='/System/Library/Fonts/'; S=F+'Supplemental/'
FONTS=[ # slug, file, full name, tracking (em fraction)
 ('din','%sDIN Alternate Bold.ttf'%S,None,0.06),
 ('futura','%sFutura.ttc'%S,'Futura Bold',0.04),
 ('avenir','%sAvenir Next.ttc'%F,'Avenir Next Heavy',0.03),
 ('helvetica-cond','%sHelveticaNeue.ttc'%F,'Helvetica Neue Condensed Black',0.02),
 ('menlo','%sMenlo.ttc'%F,'Menlo Bold',0.0),
 ('rockwell','%sRockwell.ttc'%S,'Rockwell-Bold',0.03),
 ('gill','%sGillSans.ttc'%S,'Gill Sans Bold',0.05),
 ('didot','%sDidot.ttc'%S,'Didot Bold',0.06),
]
def load(path,name):
    if path.endswith('.ttc'):
        for f in TTCollection(path).fonts:
            if f['name'].getDebugName(4)==name: return f
        raise SystemExit('missing '+name+' in '+path+': '+str([f['name'].getDebugName(4) for f in TTCollection(path).fonts]))
    return TTFont(path)
CAP=120; H=256
for slug,path,name,track in FONTS:
    f=load(path,name); gs=f.getGlyphSet(); cmap=f.getBestCmap(); upm=f['head'].unitsPerEm
    cap=getattr(f['OS/2'],'sCapHeight',0) or 0
    if not cap:
        from fontTools.pens.boundsPen import BoundsPen
        bp=BoundsPen(gs); gs[cmap[ord('H')]].draw(bp); cap=bp.bounds[3]
    s=CAP/cap; x=0; paths=[]
    names=[cmap[ord(c)] for c in 'ASM']
    for i,g in enumerate(names):
        pen=SVGPathPen(gs); tp=TransformPen(pen,(s,0,0,-s,x,H/2+CAP/2)); gs[g].draw(tp)
        paths.append(pen.getCommands())
        x+=f['hmtx'][g][0]*s + track*upm*s
    x-=track*upm*s
    pad=24; W=x+2*pad
    d=' '.join(paths)
    open(f'asm-{slug}.svg','w').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-pad:.1f} 0 {W:.1f} {H}"><title>ASM wordmark ({name or "DIN Alternate Bold"})</title><path d="{d}"/></svg>\n')
    print(slug, round(W))
