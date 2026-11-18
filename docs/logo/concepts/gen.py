A='<path d="M40 72 68 44 128 104 188 44 216 72 128 160Z"/><path d="M56 152H97.4L128 182.6 158.6 152H200a28 28 0 0 1 0 56H56a28 28 0 0 1 0-56Z"/>'
B='<path d="M36 220 100 36H156L220 220H176L128 82 80 220Z"/><rect x="112" y="166" width="32" height="32" rx="6"/>'
C='<path fill-rule="evenodd" d="M64 36H136A28 28 0 0 1 164 64V136A28 28 0 0 1 136 164H64A28 28 0 0 1 36 136V64A28 28 0 0 1 64 36ZM120 92H192A28 28 0 0 1 220 120V192A28 28 0 0 1 192 220H120A28 28 0 0 1 92 192V120A28 28 0 0 1 120 92Z"/>'
W='<path d="M300 184 339 72H373L412 184H385.2L356 100 326.8 184Z"/><rect x="346.3" y="151" width="19.5" height="19.5" rx="3.6"/><path fill="none" stroke="#000" stroke-width="26" transform="translate(24 0)" d="M457.5 106.5A21.5 21.5 0 1 0 436 128A21.5 21.5 0 1 1 414.5 149.5"/><path transform="translate(28 0)" d="M494 184V72H522L542 118 562 72H590V184H564V126L550 158H534L520 126V184Z"/>'
def w(f,vb,b): open(f,'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}">{b}</svg>\n')
for n,s in (('a',A),('b',B),('c',C)):
    w(f'{n}-symbol.svg','0 0 256 256',s); w(f'{n}-lockup.svg','0 0 650 256',s+W)
