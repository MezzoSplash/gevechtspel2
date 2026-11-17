// seeded rng
function rng(s){return function(){s|=0;s=s+0x6D2B79F5|0;let t=Math.imul(s^s>>>15,1|s);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
let UID=0;
// cut-crystal polygon: chamfers [tl,tr,br,bl] at odd sizes -> every piece reads as cut, not as a UI rectangle
function poly(w,h,c){const[a,b,cc,d]=c;return[[a,0],[w-b,0],[w,b],[w,h-cc],[w-cc,h],[d,h],[0,h-d],[0,a]].filter((p,i,arr)=>true)}
function shard(el,w,h,o){
 o=o||{};const c=o.cuts||[14,6,18,8],seed=o.seed||1,r=rng(seed*977+13),id='s'+(UID++);
 const col=o.color||null,seam=o.seam||'left',lit=o.lit==null?1:o.lit,pale=!!o.pale,alpha=o.alpha==null?.62:o.alpha;
 const pts=poly(w,h,c),cx=w*(.25+.5*r()),cy=h*(.25+.5*r());
 let f='';
 for(let i=0;i<pts.length;i++){const p=pts[i],q=pts[(i+1)%pts.length];
  const light=r()<.55;const op=(light?.04+.11*r():.05+.2*r());
  f+=`<polygon points="${p} ${q} ${cx},${cy}" fill="${light?(pale?'#fff':'#cfe6ff'):'#000'}" opacity="${op}"/>`;}
 const base=pale?'#E4EBF2':'#0F141B';
 // seam: the glowing line of the crystal (team colour), on one edge, partial length for meters
 let sm='';
 if(col){let a,b;
  if(seam=='left'){a=pts[7];b=pts[6];}
  else if(seam=='bottom'){a=pts[5];b=pts[4];}
  else if(seam=='top'){a=pts[0];b=pts[1];}
  else if(seam=='right'){a=pts[2];b=pts[3];}
  const mx=a[0]+(b[0]-a[0])*lit,my=a[1]+(b[1]-a[1])*lit;
  sm=`<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" stroke="${col}" stroke-opacity=".25" stroke-width="4"/><line x1="${a[0]}" y1="${a[1]}" x2="${mx}" y2="${my}" stroke="${col}" stroke-width="4.5" stroke-linecap="round" filter="url(#glow)"/>`;}
 el.classList.add('sh');el.style.width=w+'px';el.style.height=h+'px';
 const inner=el.innerHTML;
 el.innerHTML=`<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><polygon points="${pts}" fill="${base}" fill-opacity="${pale?.96:alpha}"/>${f}<polygon points="${pts}" fill="none" stroke="#fff" stroke-opacity="${pale?.0:.16}" stroke-width="1"/>${sm}</svg><div class="c">${inner}</div>`;
}
function defs(){document.body.insertAdjacentHTML('afterbegin',`<svg width="0" height="0" style="position:absolute"><defs><filter id="glow" filterUnits="userSpaceOnUse" x="-200" y="-200" width="2400" height="1600"><feGaussianBlur stdDeviation="4.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs></svg>`)}
// low-poly flat-shaded arena backdrop: muted foundry palette, warm key from the right (stand-in for the untouched 3D scene)
function backdrop(mode){
 const cv=document.createElement('canvas');cv.id='bg';cv.width=1920;cv.height=1080;document.body.prepend(cv);
 const g=cv.getContext('2d'),r=rng(7);
 const sky=g.createLinearGradient(0,0,0,700);sky.addColorStop(0,'#242a33');sky.addColorStop(.6,'#6b5a4c');sky.addColorStop(1,'#b0875b');
 g.fillStyle=sky;g.fillRect(0,0,1920,1080);
 // faceted layers
 function ridge(base,amp,col,steps,seed){const rr=rng(seed);const top=[];for(let i=0;i<=steps;i++)top.push([i*1920/steps,base-rr()*amp]);
  for(let i=0;i<steps;i++){const p=top[i],q=top[i+1];const k=.75+rr()*.5;g.fillStyle=shade(col,k);g.beginPath();g.moveTo(p[0],p[1]);g.lineTo(q[0],q[1]);g.lineTo(q[0],1080);g.lineTo(p[0],1080);g.fill();
   g.fillStyle=shade(col,k*(.8+rr()*.3));g.beginPath();g.moveTo(p[0],p[1]);g.lineTo(q[0],q[1]);g.lineTo((p[0]+q[0])/2,p[1]+(q[1]-p[1])/2+60+rr()*80);g.fill();}}
 function shade(c,k){const n=parseInt(c.slice(1),16);const R=Math.min(255,(n>>16)*k),G=Math.min(255,((n>>8)&255)*k),B=Math.min(255,(n&255)*k);return`rgb(${R|0},${G|0},${B|0})`}
 ridge(560,170,'#3a3f48',14,3);ridge(640,130,'#2a2e36',11,9);
 // towers (crystal-ish prisms)
 for(let i=0;i<7;i++){const x=120+i*270+r()*80,w=90+r()*90,h=240+r()*260,y=700-h*.5;
  g.fillStyle=shade('#303540',.8+r()*.4);g.beginPath();g.moveTo(x,720);g.lineTo(x+w*.15,y);g.lineTo(x+w*.7,y-30-r()*40);g.lineTo(x+w,720);g.fill();
  g.fillStyle='rgba(255,190,120,'+(.05+.1*r())+')';g.beginPath();g.moveTo(x+w*.7,y-30);g.lineTo(x+w,720);g.lineTo(x+w*.55,720);g.fill();}
 // floor facets
 const gx=24,gy=9;const pts=[];for(let j=0;j<=gy;j++){pts[j]=[];for(let i=0;i<=gx;i++)pts[j][i]=[i*1920/gx+(r()-.5)*40,720+Math.pow(j/gy,1.7)*360+(r()-.5)*14]}
 for(let j=0;j<gy;j++)for(let i=0;i<gx;i++){const a=pts[j][i],b=pts[j][i+1],c=pts[j+1][i+1],d=pts[j+1][i];const k=.55+r()*.5+(i/gx)*.25;
  g.fillStyle=shade('#4a463f',k*(1-j/gy*.55));g.beginPath();g.moveTo(...a);g.lineTo(...b);g.lineTo(...c);g.fill();
  g.fillStyle=shade('#4a463f',k*(.8+r()*.3)*(1-j/gy*.55));g.beginPath();g.moveTo(...a);g.lineTo(...c);g.lineTo(...d);g.fill();}
 // warm light bloom
 const bl=g.createRadialGradient(1500,520,10,1500,520,700);bl.addColorStop(0,'rgba(255,170,90,.45)');bl.addColorStop(1,'rgba(255,170,90,0)');g.fillStyle=bl;g.fillRect(0,0,1920,1080);
 if(mode=='dark'){g.fillStyle='rgba(8,10,14,.62)';g.fillRect(0,0,1920,1080)}
 const v=g.createRadialGradient(960,540,420,960,540,1180);v.addColorStop(0,'rgba(0,0,0,0)');v.addColorStop(1,'rgba(0,0,0,.6)');g.fillStyle=v;g.fillRect(0,0,1920,1080);
}
