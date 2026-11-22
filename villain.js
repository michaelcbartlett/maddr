// villain.js — the Mad Villain main sprite: pixel painter (albedo + height), modular hi-res villain,
// modular weapon (with aiming arm), live animated overlays, and height/normal map generation.
// Loaded by index.html BEFORE the main game script. Uses game globals at call time:
// build, CNT, S, D, ITEMS, AMMO, FRAMES, wornCore(), mkCanvas, outlined, tint, clamp, P.
'use strict';
// =============== PIXEL PAINTER (albedo + height) ===============
// hue-shifted shading: shadows drift toward cool blue-violet and gain saturation, highlights drift toward warm yellow.
function rgb2hsl(r,g,b){r/=255;g/=255;b/=255;const mx=Math.max(r,g,b),mn=Math.min(r,g,b),l=(mx+mn)/2;let h=0,s=0;
  if(mx!==mn){const d=mx-mn;s=l>.5?d/(2-mx-mn):d/(mx+mn);h=mx===r?(g-b)/d+(g<b?6:0):mx===g?(b-r)/d+2:(r-g)/d+4;h*=60;}return[h,s,l];}
function hsl2hex(h,s,l){h=((h%360)+360)%360;const f=n=>{const k=(n+h/30)%12,a=s*Math.min(l,1-l);return Math.round(255*(l-a*Math.max(-1,Math.min(k-3,9-k,1))));};
  return'#'+((1<<24)|(f(0)<<16)|(f(8)<<8)|f(4)).toString(16).slice(1);}
function shade(hex,a){const c=parseInt(hex.slice(1),16);let[h,s,l]=rgb2hsl(c>>16,c>>8&255,c&255);const f=Math.min(1,Math.abs(a));
  const toward=(h0,t,amt)=>h0+(((t-h0+540)%360)-180)*amt;
  if(a<0){if(s<.06)h=235;h=toward(h,235,f*.28);s=Math.min(1,s+f*.18);l=l*(1-f);}
  else{if(s<.06)h=50;h=toward(h,52,f*.2);if(s<.06)s=Math.min(1,s+f*.12);l=l+(1-l)*f;}
  return hsl2hex(h,s,l);}
// selective outline (replaces outlined(...,1) for villain + weapons): each outline pixel is a dark, cool version of the
// colour it borders, a touch lighter on top edges (lit side), so the silhouette reads without a flat black line.
function selOutline(src){const w=src.width,h=src.height,W=w+2,H=h+2,c=mkCanvas(W,H),g=c.getContext('2d');g.drawImage(src,1,1);
  const im=g.getImageData(0,0,W,H),d=im.data,a=new Uint8Array(W*H);for(let i=0;i<W*H;i++)a[i]=d[i*4+3]>0?1:0;
  for(let y=0;y<H;y++)for(let x=0;x<W;x++){const i=y*W+x;if(a[i])continue;let best=-1,top=false;
    for(const[dx,dy]of[[0,1],[0,-1],[1,0],[-1,0]]){const X=x+dx,Y=y+dy;if(X<0||Y<0||X>=W||Y>=H)continue;const j=Y*W+X;if(a[j]&&(best<0||d[j*4+3]>d[best*4+3])){best=j;top=dy===1;}}
    if(best<0)continue;const k=top?.4:.24;
    d[i*4]=Math.round(d[best*4]*k*.8+12);d[i*4+1]=Math.round(d[best*4+1]*k*.8+8);d[i*4+2]=Math.round(d[best*4+2]*k+24);d[i*4+3]=255;}
  g.putImageData(im,0,0);return c;}
// Height is stored in pixel units (1 unit = 1 world px toward the camera). HMAX maps to 255 in exported height maps.
const HMAX=40;
function depthBuf(w,h){return{w,h,z:new Float32Array(w*h),a:new Uint8Array(w*h)};}
// height profiles (local painter coords). amp = how far the surface bulges toward the viewer at its centre.
const Prof={
  dome:(cx,cy,rx,ry,amp)=>(x,y)=>{const u=(x-cx)/(rx+.5),v=(y-cy)/(ry+.5),d=1-u*u-v*v;return d>0?amp*Math.sqrt(d):0;},
  cylV:(cx,r,amp)=>x=>{const u=(x-cx)/(r+.5),d=1-u*u;return d>0?amp*Math.sqrt(d):0;},
  cylH:(cy,r,amp)=>(x,y)=>{const u=(y-cy)/(r+.5),d=1-u*u;return d>0?amp*Math.sqrt(d):0;},
  cap:(x0,y0,x1,y1,r,amp)=>{const dx=x1-x0,dy=y1-y0,L2=dx*dx+dy*dy||1;
    return(x,y)=>{const t=Math.max(0,Math.min(1,((x-x0)*dx+(y-y0)*dy)/L2)),u=Math.hypot(x-x0-dx*t,y-y0-dy*t)/(r+.5),d=1-u*u;return d>0?amp*Math.sqrt(d):0;};},
  slab:(x0,y0,x1,y1,amp,bev=2)=>(x,y)=>{const e=Math.min(x-x0+.5,x1-x+.5,y-y0+.5,y1-y+.5);return e<=0?0:amp*Math.min(1,Math.sqrt(e/bev));},
};
// painter(g,ox,oy,Z): every rect also writes height (layer base + profile + lift) into depth buffer Z (optional).
// Drawing order is back-to-front, so later parts overwrite both colour and height, exactly like the albedo.
function painter(g,ox=0,oy=0,Z=null){
  let zb=0,zp=null,zl=0;
  const W=(X,Y,w,h)=>{if(!Z)return;const x0=Math.max(0,X),y0=Math.max(0,Y),x1=Math.min(Z.w,X+w),y1=Math.min(Z.h,Y+h);
    for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++){const i=y*Z.w+x;Z.z[i]=zb+zl+(zp?zp(x-ox,y-oy):0);Z.a[i]=1;}};
  const R=(x,y,w,h,c)=>{if(w<=0||h<=0)return;const X=Math.round(x+ox),Y=Math.round(y+oy),Wd=Math.round(w),Hd=Math.round(h);g.fillStyle=c;g.fillRect(X,Y,Wd,Hd);W(X,Y,Wd,Hd);};
  const P=(x,y,c)=>R(x,y,1,1,c);
  const box=(x,y,w,h,c)=>{R(x,y,w,h,c);R(x,y,w,1,shade(c,.32));R(x,y+h-1,w,1,shade(c,-.38));if(h>2)R(x+w-1,y+1,1,h-2,shade(c,-.15));};
  const ell=(cx,cy,rx,ry,c)=>{for(let y=-ry;y<=ry;y++){const w=Math.round(rx*Math.sqrt(Math.max(0,1-(y/(ry+.5))**2)));R(cx-w,cy+y,2*w+1,1,c);}};
  const line=(x0,y0,x1,y1,c,w=1)=>{const n=Math.max(Math.abs(x1-x0),Math.abs(y1-y0))||1;for(let i=0;i<=n;i++){const x=x0+(x1-x0)*i/n,y=y0+(y1-y0)*i/n;R(Math.round(x-(w-1)/2),Math.round(y-(w-1)/2),w,w,c);}};
  const ring=(cx,cy,r,c,a0=0)=>{const st=.7/(r+1);for(let a=0;a<6.283;a+=st)P(Math.round(cx+Math.cos(a+a0)*r),Math.round(cy+Math.sin(a+a0)*r),c);};
  const layer=(b,p)=>{zb=b;zp=p||null;zl=0;};
  const lift=v=>{zl=v||0;};
  return{R,P,box,ell,line,ring,g,layer,lift};
}
// pad a depth buffer by 1px to match outlined(...,1); outline pixels get a lowered rim height
function padDepth(Z){const w=Z.w+2,h=Z.h+2,O=depthBuf(w,h);
  for(let y=0;y<Z.h;y++)for(let x=0;x<Z.w;x++){const s=y*Z.w+x;if(Z.a[s]){const d=(y+1)*w+x+1;O.z[d]=Z.z[s];O.a[d]=1;}}
  for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*w+x;if(O.a[i])continue;let m=-1;
    for(const[dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]){const X=x+dx,Y=y+dy;if(X<0||Y<0||X>=w||Y>=h)continue;const j=Y*w+X;if(O.a[j]===1&&O.z[j]>m)m=O.z[j];}
    if(m>=0){O.z[i]=m*.75;O.a[i]=2;}}
  return O;}
function heightCanvas(Z){const c=mkCanvas(Z.w,Z.h),g=c.getContext('2d'),im=g.createImageData(Z.w,Z.h),d=im.data;
  for(let i=0;i<Z.w*Z.h;i++){if(!Z.a[i])continue;const v=Math.round(Math.max(0,Math.min(1,Z.z[i]/HMAX))*255);d[i*4]=d[i*4+1]=d[i*4+2]=v;d[i*4+3]=255;}
  g.putImageData(im,0,0);return c;}
// tangent-space normal map from height (Sobel). OpenGL convention: +X right, +Y UP (green up), +Z toward viewer.
// Height steps between parts are clamped so each part reads as its own rounded object instead of a cliff.
function normalCanvas(Z,str=1,cl=2.5){const c=mkCanvas(Z.w,Z.h),g=c.getContext('2d'),im=g.createImageData(Z.w,Z.h),d=im.data,w=Z.w,h=Z.h;
  for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*w+x;if(!Z.a[i])continue;const hc=Z.z[i];
    const H=(dx,dy)=>{const X=x+dx,Y=y+dy;if(X<0||Y<0||X>=w||Y>=h||!Z.a[Y*w+X])return-cl;const v=Z.z[Y*w+X]-hc;return v<-cl?-cl:v>cl?cl:v;};
    const gx=(H(1,-1)+2*H(1,0)+H(1,1))-(H(-1,-1)+2*H(-1,0)+H(-1,1)),gy=(H(-1,1)+2*H(0,1)+H(1,1))-(H(-1,-1)+2*H(0,-1)+H(1,-1));
    let nx=-gx/8*str,ny=gy/8*str,nz=1;const L=Math.hypot(nx,ny,nz);nx/=L;ny/=L;nz/=L;
    d[i*4]=Math.round((nx*.5+.5)*255);d[i*4+1]=Math.round((ny*.5+.5)*255);d[i*4+2]=Math.round((nz*.5+.5)*255);d[i*4+3]=255;}
  g.putImageData(im,0,0);return c;}
function mapsOf(o){return o.maps||(o.maps={height:heightCanvas(o.depth),normal:normalCanvas(o.depth)});}

// =============== MODULAR VILLAIN (hi-res, animated) ===============
// grid units are world pixels. cx,cy = body anchor (P.x,P.y). sx,sy = gun-arm pivot = FAR shoulder (backpack side)
const VG={w:60,h:68,cx:29,cy:46,sx:25,sy:30,ox:35,oy:29};   // ox,oy = near shoulder (off-hand weapon pivot)
let villainCache=null;
// POSES: 0-5 walk (6 samples of the walk cycle, what index.html uses today), 6-9 idle breathing, 10 blink,
// 11-18 the same walk cycle at 8 frames (contact, down, passing, up for each foot) - see WALK8.
// aF/aB foot stride, lF/lB foot lift, bob body drop, swing off-arm swing, tail coat-tail trail, hair spike sway, lean forward lean
// walk keyframes for ONE leg over the cycle: heel strike forward, slide back under the body, push off, swing through.
const WALK_X=[5,3,0,-3,-5,-3,0,3],WALK_LIFT=[0,0,0,0,0,2,3,2],WALK_BOB=[0,1,1,0,0,1,1,0];
function walkKey(arr,ph){const f=(((ph%1)+1)%1)*8,i=Math.floor(f),t=f-i;return arr[i]*(1-t)+arr[(i+1)%8]*t;}
function walkPose(ph){const xF=walkKey(WALK_X,ph),bob=Math.round(walkKey(WALK_BOB,ph)),prev=Math.round(walkKey(WALK_BOB,ph-.125));
  return{aF:Math.round(xF),aB:Math.round(walkKey(WALK_X,ph+.5)),lF:Math.round(walkKey(WALK_LIFT,ph)),lB:Math.round(walkKey(WALK_LIFT,ph+.5)),
    bob,swing:-Math.round(xF*.5),tail:-1-bob,hair:prev-bob,lean:1,walk:true,heelF:xF<=-4,heelB:walkKey(WALK_X,ph+.5)<=-4};}
const WALK6=[0,1,2,3,4,5],WALK8=[11,12,13,14,15,16,17,18],IDLE=[6,7,8,9],BLINK=10;
const POSES=(()=>{const a=[];
  for(let i=0;i<6;i++)a.push(walkPose(i/6));
  for(let i=0;i<4;i++)a.push({aF:0,aB:0,lF:0,lB:0,bob:i>=2?1:0,swing:i===1||i===2?1:0,tail:i>=2?-1:0,hair:i===2?1:i===3?-1:0,lean:0,breath:i===1||i===2});
  a.push(Object.assign({},a[6],{blink:true}));
  for(let i=0;i<8;i++)a.push(walkPose(i/8));
  return a;})();

function skinPal(){const mut=(CNT.mutagen||0)>0;
  return mut?{s:'#8fcf5a',L:'#d2f08e',D:'#4f9a4e',DD:'#2c5e4c',mut}:{s:'#e8a070',L:'#fcd4a2',D:'#c06a52',DD:'#86404a',mut};}
function coatPal(){const lvl=CNT.coat||0;
  return lvl?{c:'#c2c8d2',L:'#e8eae4',M:'#a2a8c4',D:'#7e84aa',DD:'#4e5278',lvl}:{c:'#eceef4',L:'#fffcf2',M:'#ced2ea',D:'#a6a8d2',DD:'#6c6c9e',lvl};}

function renderVillain(pose,opt={}){
  const c=mkCanvas(VG.w,VG.h),g=c.getContext('2d'),Z=depthBuf(VG.w,VG.h);
  const b=pose.bob,ln=pose.lean||0,U=painter(g,ln,b,Z),Lg=painter(g,0,0,Z);
  const n=id=>CNT[id]||0,core=wornCore(),anims=[],feet=[];
  const A=o=>anims.push(Object.assign(o,{x:o.x+ln,y:o.y+b,x2:o.x2!==undefined?o.x2+ln:undefined,y2:o.y2!==undefined?o.y2+b:undefined}));
  const sk=skinPal(),mut=sk.mut,skin=sk.s,skinL=sk.L,skinD=sk.D,skinDD=sk.DD;
  const icy=n('zero')>0;
  const hairC=icy?'#c8ecff':'#a8a8c0',hairL=icy?'#f4fbff':'#eceae2',hairD=icy?'#6e98d8':'#6a6894',hairDD=icy?'#3e62a8':'#3e3c66';
  const cp=coatPal(),lvl=cp.lvl,coat=cp.c,coatL=cp.L,coatM=cp.M,coatD=cp.D,coatDD=cp.DD;
  const shirt='#9fb8dc',shirtD='#6c82c0',shirtL='#d2e2ee',pants='#8c5260',pantsD='#5e3450',pantsL='#b47676';
  const boots=n('boots')>0;
  const hasPack=!!(core||n('magnet')||n('remote')||n('moon'));
  // ANCHORS (grid coords, bob+lean applied): attach points for modular gear. See villainAnchor() for world space.
  const AN={},an=(k,x,y,raw)=>{AN[k]={x:x+(raw?0:ln),y:y+(raw?0:b)};};
  an('head',29,15);an('helmet',29,6);an('brow',32,12);an('eyeFar',30,15);an('eyeNear',34,15);an('nose',37,16);an('mouth',33,21);an('ear',25,17);
  an('neck',29,25);an('chest',31,34);an('belt',31,43);an('hip',29,46);an('back',20,33);an('backpack',12,36);
  an('shoulderFar',VG.sx,VG.sy);an('shoulderNear',VG.ox,VG.oy);
  // torso height profile: a rounded barrel, shoulders sloping back, coat flaring out below the belt
  const torsoP=(x,y)=>{const r=y<29?6:Math.min(12,8.5+Math.max(0,(y-38)/4)),u=(x-29.5)/(r+.5),d=1-u*u;return(d>0?5*Math.sqrt(d):0)-(y<30?(30-y)*.7:0)-(y>46?(y-46)*.25:0);};

  // ---------- CAPE (life suck) ----------  deepest layer
  if(n('syringe')){
    U.layer(2,Prof.cylV(27,11,3));
    for(let y=27;y<=56;y++){const t=(y-27)/29,xl=Math.round(21-t*8+(y>44?pose.tail:0)),xr=Math.round(37+t*3);
      U.R(xl,y,xr-xl,1,'#7a1020');U.R(xl,y,2,1,'#540814');if((y+pose.tail)%6===0)U.R(xl+2,y,3,1,'#8e1828');if(y%5===2)U.P(xl+5,y,'#9a2030');}
    for(let x=13+pose.tail;x<40;x+=3)U.R(x,57,2,1,'#540814');
    U.layer(4,Prof.cylV(20.5,1.5,1.5));U.R(19,19,3,9,'#a01828');U.R(20,20,1,7,'#e03848');
    U.layer(4,Prof.cylV(38.5,1.5,1.5));U.R(37,19,3,9,'#a01828');U.R(38,20,1,7,'#e03848');
  }
  // ---------- BACKPACK (power core) ----------
  if(core==='isotope'){
    U.layer(5,Prof.slab(7,24,17,26,1.5,1));U.box(7,24,11,3,'#8a8a8a');U.P(8,24,'#c8c8c8');
    U.layer(4,Prof.cylV(12,6.5,4));U.R(6,27,13,18,'#24342a');
    U.layer(5,Prof.cylV(12,5.5,4.5));U.R(7,29,11,15,'#4dc81a');U.R(7,29,11,2,'#8dff4a');
    U.R(8,31,2,12,'#b8ff80');U.P(8,31,'#f0ffe0');U.R(16,31,1,12,'#3a9a14');U.R(7,31,1,12,'#2e8a10');
    U.layer(5,Prof.slab(7,45,17,47,1.5,1));U.box(7,45,11,3,'#8a8a8a');
    U.layer(6,Prof.dome(12.5,24.5,2,1,1));U.R(11,25,3,1,'#ffd23c');U.P(12,24,'#ffd23c');
    U.layer(4,Prof.cylV(12,6.5,4));for(const yy of[33,38])U.R(6,yy,13,1,'#2a3a2e');
    U.layer(6,Prof.cap(18,33,21,34,1,1));U.line(18,33,21,34,'#3a3a3a',2);
    A({k:'tank',x:7,y:31,w:11,h:13,c:'#e0ffc8'});A({k:'pulse',x:12,y:37,r:5,c:'#7dff3a',a:.18});
  }else if(core==='hamster'){
    U.layer(4,Prof.slab(18,34,21,36,1,1));U.R(18,34,4,3,'#666');U.R(18,34,4,1,'#888');
    U.layer(3,Prof.cylV(7,1,1));U.R(6,44,2,5,'#666');U.layer(3,Prof.cylV(16,1,1));U.R(15,44,2,5,'#666');
    U.layer(3,Prof.cylH(48,.5,.5));U.R(5,48,13,1,'#555');
    // wheel disc backing so the wheel has height in the maps (spokes/hamster are live overlays)
    U.layer(4,Prof.dome(11,35,9,9,2));U.ring(11,35,9,'#8a8e96');U.ring(11,35,8,'#5a5e66');
    A({k:'wheel',x:11,y:35,r:9});
  }else if(core==='battery'){
    U.layer(4,Prof.slab(5,29,19,45,4,3));U.box(5,29,15,17,'#26282c');U.R(5,29,15,3,'#c83030');U.R(5,29,15,1,'#ff6a6a');
    U.R(6,32,1,13,'#3a3e44');U.R(18,32,1,13,'#18191c');
    U.layer(6,Prof.dome(8,27,1.5,1.5,1.5));U.box(7,26,3,3,'#c83030');U.P(8,27,'#fff');
    U.layer(6,Prof.dome(16,27,1.5,1.5,1.5));U.box(15,26,3,3,'#9aa4ae');U.P(16,27,'#222');
    U.layer(8.5,Prof.slab(8,36,16,40,.6,1));U.R(8,36,9,5,'#ffd23c');U.R(10,37,3,1,'#26282c');U.R(12,38,3,1,'#26282c');U.R(11,39,2,1,'#26282c');
    A({k:'spark',x:8,y:25});A({k:'spark',x:16,y:25});
  }else if(core==='brain'){ // brain in a jar
    U.layer(5,Prof.slab(5,22,19,24,1.5,1));U.box(5,22,15,3,'#7a7a7a');
    U.layer(4,Prof.cylV(12,7.5,5));U.R(5,25,15,20,'#5fa6b8');U.R(6,26,13,18,'#9ed8e6');U.R(6,26,2,18,'#dcf4fa');U.R(18,26,1,18,'#78b8c8');
    U.layer(5,Prof.dome(12,34,5,4,4));U.ell(12,34,5,4,'#ff8fb0');U.R(9,32,1,4,'#d0607e');U.R(12,31,1,5,'#d0607e');U.R(15,33,1,3,'#d0607e');U.R(10,30,4,1,'#ffc0d4');
    U.R(12,38,1,5,'#e07090');
    U.layer(5,Prof.slab(5,45,19,47,1.5,1));U.box(5,45,15,3,'#7a7a7a');
    A({k:'jar',x:7,y:27,w:11,h:16});A({k:'pulse',x:12,y:34,r:4,c:'#ff8fb0',a:.15});
  }
  if(!core&&(n('magnet')||n('remote')||n('moon'))){U.layer(4,Prof.slab(8,27,17,41,3,2));U.box(8,27,10,15,'#5a5e66');U.R(9,30,8,1,'#3a3e46');U.R(9,35,8,1,'#3a3e46');U.P(16,29,'#3f3');}
  if(n('magnet')){U.layer(3,Prof.slab(2,9,13,21,2.5,2));U.R(2,9,4,12,'#d83030');U.R(10,9,4,12,'#d83030');U.R(2,18,12,4,'#d83030');U.R(2,9,1,13,'#ff7a7a');U.R(10,9,1,9,'#ff7a7a');U.R(2,21,12,1,'#8a1818');
    U.layer(4,Prof.slab(2,7,13,9,1.5,1));U.box(2,7,4,3,'#e8e8f0');U.box(10,7,4,3,'#e8e8f0');U.layer(4,Prof.cylV(7.5,1,1));U.R(7,22,2,3,'#555');A({k:'spark',x:8,y:5,c:'#8fd8ff'});}
  if(n('remote')){U.layer(5,Prof.cap(18,25,20,6,1,.8));U.line(18,25,20,6,'#8a8a8a');U.R(17,24,3,2,'#333');A({k:'led',x:20,y:5,c:'#ff3030'});}
  if(n('moon')){U.layer(4,Prof.cap(9,24,8,13,1,1));U.line(9,24,8,13,'#777',2);
    U.layer(5,Prof.cylH(11.5,2,1.5));U.R(1,12,14,1,'#e8e8f0');U.R(2,11,12,1,'#c8c8d0');U.R(4,10,8,1,'#a8a8b0');U.R(2,13,12,1,'#8a8a92');U.R(7,6,2,4,'#888');A({k:'led',x:7,y:5,c:'#ff3030'});}

  // ---------- HAIR (back mass) ----------  behind the head, roots dark, tips light
  const spL=[1,3,4,6,8,9,8,10,11,10,12,11,9,10,8,9,7,5,4,2,1];
  const hb=pose.hurt?2:pose.hair;
  U.layer(9,Prof.dome(23,14,11,11,6));
  for(let i=0;i<spL.length;i++){const y=4+i,x0=23-spL[i]-(i%3===0&&i>3?hb:0);
    U.R(x0,y,26-x0,1,hairC);U.R(22,y,4,1,hairD);U.P(x0,y,i%2?hairL:hairD);
    if(spL[i]>3){U.R(x0+3,y,2,1,hairD);U.P(x0+1,y,hairL);U.P(x0+6,y,hairL);}}
  for(let i=0;i<spL.length;i+=4){const y=5+i;U.R(23-spL[i]+2,y,4,1,hairDD);}
  const spR=[2,4,5,7,6,4,3,2];
  U.layer(10,Prof.dome(35,8,6,5,4));
  for(let i=0;i<spR.length;i++){const y=4+i,dx=i>=2&&i<=4?hb:0;U.R(32,y,spR[i]+3+dx,1,hairC);U.P(34+spR[i]+dx,y,hairL);U.P(33,y,hairD);if(spR[i]>4)U.P(36,y,hairL);}
  U.layer(12,null);
  U.line(25,8,22-hb,2,hairC);U.line(28,7,28,1+Math.abs(hb),hairC);U.line(31,7,33+hb,2,hairC);U.line(26,8,24-hb,4,hairD);
  U.P(22-hb,2,hairL);U.P(28,1+Math.abs(hb),hairL);U.P(33+hb,2,hairL);

  // ---------- LEGS ----------  thigh hidden by coat, shin + sneaker visible
  const seg=(P,x0,y0,x1,y1,pc,pcD,pcL)=>{const n2=Math.max(1,y1-y0);for(let y=y0;y<=y1;y++){const x=Math.round(x0+(x1-x0)*(y-y0)/n2);P.R(x-2,y,5,1,pc);P.P(x-2,y,pcD);P.P(x+2,y,pcL);}};
  const leg=(hx,ax,lift,back)=>{
    const pc=back?pantsD:pants,pcD=back?'#3c2240':pantsD,pcL=back?pants:pantsL,base=back?6:13;
    const hipY=46+b,fy=58-lift,fx=hx+ax,ky=50,kx=Math.round(hx+ax*.45+(lift?1.5:0)),heel=back?pose.heelB:pose.heelF,nm=back?'Back':'Front';
    an('knee'+nm,kx,ky,1);an('foot'+nm,fx+1,fy+3,1);
    Lg.layer(base,Prof.cap(hx,hipY,kx,ky,2.5,2.5));seg(Lg,hx,hipY,kx,ky,pc,pcD,pcL);
    Lg.layer(base,Prof.cap(kx,ky,fx,fy-1,2.5,2.5));seg(Lg,kx,ky,fx,fy-1,pc,pcD,pcL);Lg.R(fx-2,fy-1,5,1,pcD);
    const toe=lift>0?-1:0;
    if(boots){const bc=back?'#a01e1e':'#c82828';Lg.layer(base+1,Prof.dome(fx+1,fy,4.5,3,2.5));
      Lg.box(fx-3,fy-3,8,6,bc);Lg.R(fx-3,fy-3,8,1,back?'#d04a4a':'#ff6a6a');Lg.R(fx+4,fy-1+toe,2,3,bc);Lg.P(fx+5,fy-1+toe,back?'#d04a4a':'#ff6a6a');
      Lg.layer(base,Prof.cylV(fx-4.5,1,1));Lg.box(fx-5,fy-2,2,4,'#5a5a5a');Lg.layer(base,null);Lg.R(fx-3,fy+3,9,1,'#2a2a2a');
      Lg.layer(base+2,null);Lg.P(fx,fy-1,'#ffd23c');feet.push({x:fx-4,y:fy+2});}
    else{const sc=back?'#c0c0d6':'#eeeef6',scL=back?'#dcdce8':'#fffcf2',scD=back?'#9494b8':'#babad6';
      Lg.layer(base+1,Prof.dome(fx+1,fy+1,4.5,2.5,2.5));
      Lg.R(fx-3,fy,7,1,sc);Lg.R(fx-3,fy+1,9,2,sc);Lg.R(fx+4,fy+toe,2,1,sc);   // upper + toe box
      Lg.R(fx-2,fy,5,1,scL);Lg.R(fx+3,fy+1+toe,2,1,scL);Lg.R(fx-3,fy+1,1,2,scD);Lg.P(fx+5,fy+2,scD);
      Lg.P(fx-1,fy,'#9aa4c0');Lg.P(fx+1,fy,'#9aa4c0');Lg.P(fx,fy+1,'#9aa4c0');           // laces
      Lg.layer(base,null);if(heel){Lg.R(fx-1,fy+3,7,1,'#7c7c98');Lg.g.clearRect(fx-3,fy+2,2,1);Lg.R(fx-3,fy+2,2,1,'#5e5e80');}
      else{Lg.R(fx-3,fy+3,9,1,'#7c7c98');Lg.R(fx-3,fy+3,3,1,'#5e5e80');}   // sole
      feet.push({x:fx-3,y:fy+2});}
  };
  leg(26,pose.aB,pose.lB,true);
  leg(31,pose.aF,pose.lF,false);

  // ---------- OFF ARM (near shoulder, BEHIND the torso: coat overlaps it, forearm + orb hand peek out front) ----------
  const ax0=VG.ox,ay0=VG.oy,hx=40+pose.swing,hy=41,ex=38+Math.round(pose.swing/2),ey=35;
  an('elbowOff',ex,ey);an('handOff',hx,hy+1);
  if(!opt.armed){
  for(const[x0,y0,x1,y1]of[[ax0,ay0,ex,ey],[ex,ey,hx,hy-2]]){U.layer(9,Prof.cap(x0,y0,x1,y1,2.5,2.5));U.line(x0,y0,x1,y1,coatDD,5);}
  for(const[x0,y0,x1,y1]of[[ax0,ay0,ex,ey],[ex,ey,hx,hy-2]]){U.layer(9,Prof.cap(x0,y0,x1,y1,2.5,2.5));U.line(x0,y0,x1,y1,coatM,3);U.line(x0-1,y0+1,x1-1,y1,coatD,1);U.line(x0+1,y0-1,x1+1,y1-1,coat,1);}
  U.layer(9,Prof.dome(ex,ey,2,2,2.5));U.P(ex-1,ey+1,coatD);U.P(ex-2,ey,coatD);                // elbow crease
  U.layer(9,Prof.cap(hx-1,hy-2,hx+1,hy-2,1.5,2));U.R(hx-2,hy-2,5,2,coatM);U.R(hx-2,hy-2,5,1,coat);U.P(hx-2,hy-1,coatD);  // cuff
  if(n('orb')){U.lift(.8);U.R(hx-2,hy-4,4,2,'#c99a3a');U.R(hx-2,hy-4,4,1,'#ffe08a');U.P(hx,hy-4,'#7dff3a');U.lift(0);}
  U.layer(10,Prof.dome(hx,hy+1,2,2,2));U.box(hx-1,hy,3,3,skin);U.P(hx,hy,skinL);U.P(hx-1,hy+2,skinD);
  }else{ // off hand is holding the second weapon: only the shoulder cap shows, the arm itself lives on the off-weapon canvas
    U.layer(9,Prof.dome(ax0,ay0,2.5,2.5,2.5));U.ell(ax0,ay0+1,2,2,coatM);U.P(ax0,ay0,coat);}
  // ---------- COAT ----------
  U.layer(12,torsoP);
  for(let y=27;y<=51;y++){
    let xl,xr;if(y===27){xl=24;xr=34;}else if(y===28){xl=22;xr=36;}else{xl=21-Math.max(0,Math.floor((y-38)/4));xr=37+Math.max(0,Math.floor((y-40)/5));}
    if(pose.breath&&y>=29&&y<=40)xr++;
    if(y>=46)xl+=pose.tail;if(y===51){xl+=1;xr-=1;}
    if(y<=28){U.R(xl,y,xr-xl+1,1,coatM);U.R(xl+2,y,xr-xl-3,1,y===27?coatL:coat);continue;}
    U.R(xl,y,29-xl,1,coat);U.R(33,y,xr-32,1,coat);
    U.P(xl,y,coatDD);U.R(xl+1,y,2,1,coatD);U.P(xl+3,y,coatM);     // back side falls into shadow
    U.P(33,y,coatM);U.P(xr-1,y,coatL);U.P(xr,y,coatM);            // front edge catches the light
    if(y>=44){U.lift(-.9);U.P(25+(y>48?-1:0)+(y>=46?pose.tail:0),y,coatM);U.P(35+(y>49?1:0),y,coatM);U.lift(0);}  // folds (creased in the height map too)
    if(y>=31&&y<=37&&(y&1)){U.lift(-.5);U.P(24+(y>34?1:0),y,coatM);U.lift(0);}                                  // drag folds under the arm
    if(y>=47){U.P(28,y,coatD);U.P(33,y,coatD);}
  }
  U.R(22+pose.tail,51,7,1,coatDD);U.R(33,51,5,1,coatDD);U.R(23+pose.tail,50,5,1,coatD);U.R(33,50,4,1,coatM);
  U.R(22,29,3,1,coatM);                                            // shoulder seam (far side)
  // shirt (recessed), belt, pants top
  U.lift(-.6);U.R(29,28,4,16,shirt);U.R(29,28,1,16,shirtD);U.R(32,29,1,13,shirtL);for(const yy of[31,35,39])U.P(31,yy,'#5a70a0');
  U.lift(.6);U.R(28,26,2,3,'#dce8fa');U.R(32,26,2,3,'#dce8fa');U.P(29,28,'#9ab0d8');U.P(33,26,'#ffffff');
  U.lift(.3);U.R(29,42,4,2,'#3a2818');U.R(30,42,2,2,'#c9a227');U.P(30,42,'#fff0a0');U.R(29,44,4,3,pants);U.P(29,44,pantsD);
  // lapels / pockets / pens
  U.lift(1);U.R(27,28,2,8,coatD);U.R(28,28,1,7,coatL);U.R(33,28,1,8,coatD);U.R(34,29,1,5,coatL);U.P(28,35,coatM);
  U.lift(.4);U.R(22,42,5,1,coatD);U.R(22,43,1,3,coatM);U.R(34,38,3,1,coatD);
  U.lift(1.2);U.R(34,35,1,3,'#3a6ad8');U.R(35,34,1,4,'#d83a3a');U.P(34,35,'#8ab0ff');U.P(35,34,'#ff9a9a');
  U.lift(0);
  // lead lining
  if(lvl){U.lift(.4);for(const[x,y]of[[24,31],[24,37],[24,43],[36,37],[36,43],[26,49]])U.P(x,y,'#4a4a52');U.lift(0);U.R(25,29,1,22,shade(coat,-.12));}
  if(lvl>=2){U.layer(15,Prof.dome(23,27,4,3,2.5));U.box(19,25,8,5,'#6a7282');U.P(21,26,'#aab');U.P(24,26,'#aab');U.R(20,25,6,1,'#9aa2b2');U.layer(12,torsoP);}
  if(lvl>=3){U.lift(1.5);U.box(28,29,6,11,'#7a8292');U.R(29,30,4,1,'#9aa2b2');U.P(29,31,'#444');U.P(32,31,'#444');U.P(29,37,'#444');U.P(32,37,'#444');U.lift(0);}
  // backpack strap
  if(hasPack){U.lift(.8);U.R(21,28,2,12,'#4a3424');U.R(21,28,1,12,'#5e4430');U.R(21,33,2,2,'#c9a227');U.P(21,33,'#fff0a0');U.lift(0);}
  // coat decorations
  if(n('bleed')){U.lift(.1);for(const[x,y]of[[25,35],[26,36],[24,37],[35,40],[36,41],[36,39],[24,48],[34,47],[35,48]])U.P(x,y,'#a01020');U.lift(0);}
  if(n('acid')){U.lift(.1);U.R(22,49,3,2,'#b8c830');U.R(35,45,2,3,'#b8c830');U.P(23,50,'#1a1a1a');U.P(36,46,'#1a1a1a');U.P(24,46,'#d8e840');U.lift(0);}
  if(n('nuke')){U.lift(1);U.box(23,36,5,5,'#ffd23c');U.P(25,38,'#222');U.P(24,37,'#222');U.P(26,37,'#222');U.P(25,39,'#222');U.lift(0);}
  if(n('hypno')){U.layer(15,Prof.dome(25,46,2,2,1.5));U.ell(25,46,2,2,'#9a40d0');U.P(25,46,'#fff');U.P(26,45,'#f0c8ff');U.P(24,47,'#f0c8ff');U.layer(12,torsoP);}
  if(n('reactor')){U.layer(17,Prof.dome(31,34,3,3,2));U.ell(31,34,3,3,'#2f6a2a');U.ell(31,34,2,2,'#7dff3a');U.P(31,34,'#e8ffe0');U.P(30,33,'#c8ffb0');U.layer(12,torsoP);A({k:'pulse',x:31,y:34,r:3,c:'#7dff3a',a:.35});}
  if(n('grenade')){U.lift(1.2);U.line(24,28,35,45,'#5a4020',2);U.line(25,28,36,45,'#7a5a30');
    for(const t of[.25,.5,.75]){const x=Math.round(24+11*t),y=Math.round(28+17*t);U.lift(2.2);U.ell(x+1,y,1,2,'#4a6a2a');U.P(x+1,y-1,'#6a8a3a');U.P(x+1,y-3,'#ccc');}U.lift(0);}
  if(n('greed')){U.lift(1);U.line(25,27,31,33,'#e8c030');U.line(31,33,36,27,'#e8c030');U.layer(16,Prof.dome(31,35,2,2,1.5));U.ell(31,35,2,2,'#ffd23c');U.P(31,35,'#b08a18');U.P(30,34,'#fff6c0');U.layer(12,torsoP);}
  // belt rig (vials, clock)
  const belt=[];if(n('serum'))belt.push('#7dff3a');if(n('acid'))belt.push('#e8f040');if(n('poison'))belt.push('#3ad83a');if(n('virus'))belt.push('#b0d030');
  if(belt.length||n('clock')){U.lift(1);U.R(33,42,10,2,'#3a2818');U.R(33,42,10,1,'#5a4028');let x=34;
    for(const col of belt){U.layer(15,Prof.cylV(x+.5,1,1.2));U.R(x,44,2,5,col);U.P(x,44,shade(col,.5));U.P(x,45,shade(col,.3));U.R(x,48,2,1,shade(col,-.3));U.R(x,43,2,1,'#d8d8e0');U.R(x,42,2,1,'#a07040');x+=3;}
    if(n('clock')){U.layer(15,Prof.dome(x+2,46,2,2,1.5));U.ell(x+2,46,2,2,'#eee');U.P(x,43,'#c33');U.P(x+4,43,'#c33');U.P(x+2,46,'#222');U.R(x,48,5,1,'#c8302a');A({k:'clock',x:x+2,y:46});}
    U.layer(12,torsoP);}


  // ---------- HEAD ----------
  U.layer(13,Prof.cylV(29,3,2));U.R(26,22,6,6,skinD);U.R(27,22,4,5,skin);U.P(30,23,skinL);
  U.layer(16,Prof.dome(29,15,7,8,7));
  U.ell(29,15,7,8,skin);
  U.R(22,11,2,10,skinD);U.R(23,9,1,2,skinD);U.R(22,13,1,6,skinDD);U.R(24,8,2,1,skinD);    // back of skull in shadow
  U.ell(31,10,3,2,skinL);U.P(30,9,'#fff8f0');U.P(32,9,'#fff8f0');U.P(34,11,skinL);           // crown sheen
  U.R(25,21,11,3,skin);U.R(25,23,11,1,skinD);U.R(25,21,1,2,skinD);
  U.lift(.6);U.R(24,15,3,5,skinD);U.R(25,16,1,3,skinDD);U.P(26,15,skin);U.lift(0);           // ear
  U.lift(-.5);U.R(29,11,1,1,skinD);U.R(31,10,3,1,skinD);U.P(28,12,skinD);U.lift(0);            // forehead furrows
  if(mut){U.line(26,9,27,13,skinDD);U.P(33,8,skinDD);U.P(34,9,skinDD);U.ell(25,11,1,1,skinL);}
  // sunken eye sockets
  U.lift(-1.6);U.R(28,13,4,1,skinDD);U.R(33,13,3,1,skinDD);U.R(28,14,1,3,skinD);U.R(29,17,3,1,skinD);U.R(33,17,3,1,skinD);U.P(36,14,skinD);
  // eyes
  U.lift(-1.2);U.R(29,14,3,3,'#1c1214');U.R(33,14,3,3,'#1c1214');
  if(pose.blink){U.lift(-1);U.R(29,14,3,3,skinD);U.R(33,14,3,3,skinD);U.R(29,16,3,1,skinDD);U.R(33,16,3,1,skinDD);}
  else if(n('hypno')||n('hive')){U.P(30,15,'#d07bff');U.P(31,15,'#fff');U.P(34,15,'#d07bff');U.P(35,15,'#fff');}
  else{U.P(31,15,'#ffffff');U.P(35,15,'#ffffff');U.P(30,16,'#5a3a3a');U.P(34,16,'#5a3a3a');}
  U.lift(.2);U.P(32,15,skin);                                                                  // nose bridge between sockets
  // brows (angry, overhanging the sockets)
  U.lift(1.4);U.R(27,12,3,1,hairC);U.R(29,13,3,1,hairC);U.R(33,13,2,1,hairC);U.R(34,12,3,1,hairC);U.P(27,11,hairL);U.P(36,11,hairL);U.P(30,13,hairD);U.P(34,13,hairD);
  U.lift(0);
  if(pose.hurt){U.lift(-1.2);U.R(29,14,3,3,skinD);U.R(33,14,3,3,skinD);U.R(29,15,3,1,'#1c1214');U.R(33,15,3,1,'#1c1214');U.P(28,16,skinDD);U.P(36,16,skinDD);
    U.lift(1.4);U.R(28,13,3,1,hairC);U.R(33,13,3,1,hairC);U.P(31,12,hairC);U.P(32,12,hairC);U.lift(0);}
  if(n('disint')){U.layer(19,Prof.dome(34,15,2.5,2.5,2));U.R(32,13,5,5,'#6a6a72');U.R(32,13,5,1,'#9a9aa2');U.R(33,14,3,3,'#ff2a2a');U.P(34,15,'#ffd0d0');U.P(36,13,'#aaa');A({k:'pulse',x:34,y:15,r:2,c:'#ff2a2a',a:.4});U.layer(16,Prof.dome(29,15,7,8,7));}
  if(n('monocle')){ // Targeting Monocle: huge chunky brass lens over the far eye, magnified eye behind domed glass, chain to the lapel
    const mx=n('telescope')?29:31,my=15,br='#c9a227',brL='#ffe08a',brD='#8a6a18',brDD='#5a4210';
    U.layer(21,Prof.dome(mx,my,5.5,5.5,2.2));U.ell(mx,my,5,5,brD);U.ell(mx,my,4,4,br);                    // rim (bevelled brass)
    U.P(mx-3,my-3,brL);U.P(mx-2,my-4,brL);U.P(mx-4,my-2,brL);U.P(mx-1,my-5,brL);U.P(mx+3,my+3,brDD);U.P(mx+4,my+2,brDD);U.P(mx+2,my+4,brDD);
    U.P(mx+5,my,brDD);U.P(mx,my+5,brDD);U.P(mx+4,my-3,br);U.P(mx-5,my+1,brD);                                 // rim screws/shading
    U.layer(21.5,Prof.dome(mx,my,3.5,3.5,3.2));U.ell(mx,my,3,3,'#9ccbe0');                                    // glass dome
    U.R(mx-2,my-1,4,3,'#1c1214');U.R(mx-1,my-2,2,1,'#1c1214');                                                // magnified eye
    if(!pose.blink&&!pose.hurt){U.R(mx,my-1,2,2,'#ffffff');U.P(mx-1,my+1,'#5a3a3a');}else U.R(mx-2,my,4,1,'#c06a52');
    U.P(mx-2,my-2,'#e8f8ff');U.P(mx-1,my-3,'#ffffff');U.P(mx-3,my-1,'#e8f8ff');U.P(mx+2,my+2,'#6a9ab8');U.P(mx+1,my+2,'#7aaac8');  // glints
    U.layer(19,null);for(let i=0;i<=8;i++){const t=i/8,x=Math.round(mx-4-3*t),y=Math.round(my+4+8*t);U.P(x,y,i%2?brD:br);if(i%2===0)U.P(x+1,y,brL);}  // chain
    U.layer(17,Prof.dome(24,28,1,1,1));U.R(23,27,2,2,br);U.P(23,27,brL);U.layer(16,Prof.dome(29,15,7,8,7));A({k:'glint',x:mx-2,y:my-3});}
  if(n('telescope')){ // Telescoping Monocle: spyglass eyepiece strapped over the NEAR eye. Retracted tubes are baked here;
    // the sliding extension + lens glint is the live 'tscope' overlay (extends while firing/aiming).
    const ey=15,br='#c9a227',brL='#ffe08a',brD='#8a6a18',st='#9aa4ae',stL='#d4dce4',stD='#5f6872',lth='#4a3424',lthL='#6a4a30';
    U.layer(16,Prof.dome(29,15,7,8,7));U.lift(1);U.line(33,12,23,10,lth,2);U.line(33,12,24,9,lthL);U.R(25,9,2,3,br);U.P(25,9,brL);  // head strap + buckle
    U.line(33,18,24,19,lth);U.lift(0);
    U.layer(22,Prof.dome(34,ey,2.5,2.5,2));U.ell(34,ey,2,2,brD);U.R(33,ey-1,3,3,'#1c1214');U.P(33,ey-2,brL);                       // eyecup
    U.layer(23,Prof.cylH(ey,2.5,2.5));U.R(36,ey-2,4,5,br);U.R(36,ey-2,4,1,brL);U.R(36,ey+2,4,1,brD);U.R(39,ey-2,1,5,brD);U.P(37,ey-1,'#fff4c0'); // seg 1 (brass)
    U.layer(24,Prof.cylH(ey,1.5,2));U.R(40,ey-1,2,3,st);U.R(40,ey-1,2,1,stL);U.R(40,ey+1,2,1,stD);                               // seg 2 (steel, retracted)
    U.layer(24.5,Prof.cylH(ey,1.5,2));U.R(42,ey-1,1,3,br);U.P(42,ey-1,brL);U.layer(25,Prof.dome(43,ey,.5,1.5,1.5));U.R(43,ey-1,1,3,'#9ccbe0');U.P(43,ey-1,'#ffffff'); // seg 3 + lens
    an('telescopeTip',44,ey);A({k:'tscope',x:40,y:ey});}
  // nose (big, hooked)
  U.layer(20,Prof.dome(37,16,2,3,2.5));U.R(36,14,2,5,skin);U.R(38,16,1,3,skin);U.R(36,18,3,1,skinD);U.P(37,18,skinDD);U.P(37,14,skinL);U.P(37,15,skinL);U.P(38,17,skinD);
  U.layer(16,Prof.dome(29,15,7,8,7));U.P(35,19,skinD);
  // mouth (grin) + beard
  U.lift(-1);U.R(30,20,6,2,'#3a1010');U.R(31,20,4,1,'#f0ece0');U.P(33,20,'#c8c0b0');
  if(pose.hurt){U.R(30,20,6,2,'#f0ece0');U.R(30,22,6,1,'#3a1010');U.P(31,20,'#8a6a6a');U.P(33,21,'#8a6a6a');U.P(35,20,'#8a6a6a');}
  if(n('greed'))U.P(33,20,'#ffd23c');
  if(n('syringe')){U.P(31,21,'#fff');U.P(34,21,'#fff');}
  U.layer(18,Prof.dome(32,22,5.5,3,2.5));
  U.R(29,19,8,1,hairC);U.P(29,20,hairC);U.P(36,20,hairC);U.R(28,22,9,2,hairC);U.R(29,24,7,1,hairD);U.R(27,20,2,3,hairC);
  U.P(28,24,hairD);U.P(31,25,hairD);U.P(34,25,hairC);U.P(36,24,hairD);U.R(28,23,9,1,hairD);U.R(29,22,7,1,hairC);
  U.P(30,22,hairL);U.P(33,22,hairL);U.P(35,22,hairL);U.P(30,19,hairL);U.P(34,19,hairL);U.P(27,21,hairD);
  if(n('poison')){U.layer(17,Prof.dome(31,26,4,2,2));U.ell(31,26,4,2,'#3a5a3a');U.R(28,25,7,1,'#4a6a4a');U.layer(19,Prof.cylV(36.5,1.5,1.5));U.box(35,24,3,4,'#2a2a2a');U.P(36,25,'#7dff3a');U.layer(17,null);U.P(26,26,'#222');}
  // front strands over dome
  U.layer(21,null);U.R(22,7,2,4,hairC);U.P(23,6,hairL);U.R(35,6,1,3,hairC);U.P(24,8,hairD);U.P(22,10,hairD);
  if(core==='isotope'){U.P(14,9,'#9dff4a');U.P(12,15,'#9dff4a');U.P(13,16,'#9dff4a');U.P(37,6,'#9dff4a');U.P(38,7,'#9dff4a');}
  if(n('thermite'))for(const[x,y]of[[14,9],[11,15],[15,21],[22-hb,2],[28,1],[33+hb,2],[38,6]])A({k:'flame',x,y});
  // battery cables to the brain, brain-jar electrode
  if(core==='battery'){U.layer(20,null);U.line(8,25,9,15,'#d02020');U.line(9,15,23,14,'#d02020');U.layer(21,Prof.dome(24,14,1,1.5,1));U.box(23,13,2,3,'#c83030');
    U.layer(20,null);U.line(16,25,19,19,'#222');U.line(19,19,23,19,'#222');U.layer(21,Prof.dome(24,19,1,1,1));U.box(23,18,2,2,'#555');}
  if(core==='brain'){U.layer(20,null);U.line(16,22,17,13,'#3a8ad0');U.line(17,13,23,12,'#3a8ad0');U.layer(21,Prof.dome(24,12,1,1,1));U.box(23,11,2,2,'#aaa');}
  // goggles on forehead
  if(n('goggles')){U.layer(22,Prof.cylH(9.5,1,1));U.R(22,9,15,2,'#3a3a3a');U.R(22,9,15,1,'#5a5a5a');
    for(const ex of[29,34]){U.layer(23,Prof.dome(ex,9,2,2,2));U.ell(ex,9,2,2,'#5a3a1a');U.R(ex-1,8,3,3,'#ffb030');U.P(ex-1,8,'#fff');U.P(ex+1,10,'#c06a10');}}
  // antennas
  if(n('tesla')){U.layer(20,null);U.line(24,8,20,1,'#9a9aa4');U.R(23,6,2,1,'#c97a3a');U.layer(21,Prof.dome(20,1,1,1,1));U.ell(20,1,1,1,'#fff36b');A({k:'spark',x:20,y:1});}
  if(n('storm')){U.layer(20,null);U.line(34,7,38,1,'#9a9aa4');U.R(35,5,2,1,'#c97a3a');U.layer(21,Prof.dome(38,1,1,1,1));U.ell(38,1,1,1,'#fff36b');A({k:'spark',x:38,y:1});if(n('tesla'))A({k:'arc',x:21,y:1,x2:37,y2:1});}
  // ice on shoulders
  if(n('cryo')||icy){U.layer(17,null);for(const sx of[21,36]){U.R(sx,23,1,4,'#bff4ff');U.R(sx+1,24,1,3,'#e8ffff');U.R(sx-1,25,1,2,'#9ad8f0');}A({k:'mist',x:36,y:24});}
  // hive dome
  if(n('hive')){U.layer(17,Prof.dome(29,11,10,9,8));g.globalAlpha=.32;U.ell(29,11,10,9,'#a8dcff');g.globalAlpha=1;U.layer(18,Prof.dome(29,6,5,3,3));U.ell(29,6,5,3,'#ff8fb0');U.R(27,5,1,3,'#d0607e');U.R(30,4,1,3,'#d0607e');U.R(32,6,1,2,'#d0607e');
    U.layer(19,Prof.cylH(19.5,1,1));U.R(19,19,21,2,'#9aa4ae');U.R(19,19,21,1,'#d0d8e0');U.layer(26,null);U.R(23,3,3,1,'#ffffff');U.P(21,6,'#ffffff');A({k:'pulse',x:29,y:6,r:4,c:'#ff8fb0',a:.3});}
  if(n('singular'))A({k:'sing',x:49,y:12});

  return{img:selOutline(c),depth:padDepth(Z),bob:b,lean:ln,hand:{x:hx+ln,y:hy+1+b},feet,anims,anchors:AN,pose,opt};
}
// getVillainFrames()      -> normal body (off hand holds the plasma orb)  [what index.html uses]
// getVillainFrames(true)  -> body for when the off hand holds a second weapon
function getVillainFrames(armed){if(!villainCache)villainCache=POSES.map(p=>renderVillain(p));
  if(!armed)return villainCache;return villainCache.armed||(villainCache.armed=POSES.map(p=>renderVillain(p,{armed:true})));}
function hurtFrame(f){return f.hurtFr||(f.hurtFr=renderVillain(Object.assign({},f.pose,{hurt:true}),f.opt));}
// cartoon x-ray: electric-blue silhouette + skeleton that follows the pose anchors
function zapFrame(f){if(f.zap)return f.zap;const src=hurtFrame(f),c=mkCanvas(src.img.width,src.img.height),g=c.getContext('2d');
  g.drawImage(src.img,0,0);g.globalCompositeOperation='source-in';g.fillStyle='#2848c8';g.fillRect(0,0,c.width,c.height);g.globalCompositeOperation='source-over';
  const im=g.getImageData(0,0,c.width,c.height),d=im.data,W=c.width,H=c.height;   // bright electric rim
  const on=(x,y)=>x>=0&&y>=0&&x<W&&y<H&&d[(y*W+x)*4+3]>0,rim=[];
  for(let y=0;y<H;y++)for(let x=0;x<W;x++)if(on(x,y)&&(!on(x+1,y)||!on(x-1,y)||!on(x,y+1)||!on(x,y-1)))rim.push(y*W+x);
  for(const i of rim){d[i*4]=150;d[i*4+1]=240;d[i*4+2]=255;}g.putImageData(im,0,0);
  const A=src.anchors,p=painter(g,1,1),B='#f6fbff',BD='#a8c4ff',HOLE='#0c1440';
  const bone=(a,b2,w=2)=>{if(a&&b2)p.line(a.x,a.y,b2.x,b2.y,B,w);};
  bone(A.shoulderFar,A.shoulderNear,1);                                                    // collarbones
  bone(A.neck,A.hip,2);for(let y=A.neck.y+1;y<A.hip.y;y+=3)p.P(A.neck.x-1,y,BD);          // spine
  for(let r=0;r<4;r++){const y=A.chest.y-5+r*3;p.R(A.chest.x-7+r,y,13-2*r,1,B);p.P(A.neck.x,y,BD);}   // ribs
  p.R(A.hip.x-4,A.hip.y-1,9,2,B);p.P(A.hip.x-4,A.hip.y+1,B);p.P(A.hip.x+4,A.hip.y+1,B);  // pelvis
  for(const s2 of['Back','Front']){const hip={x:A.hip.x+(s2==='Back'?-3:2),y:A.hip.y};bone(hip,A['knee'+s2]);bone(A['knee'+s2],A['foot'+s2]);
    const ft=A['foot'+s2];p.R(ft.x-2,ft.y-1,5,1,B);}
  if(!f.opt.armed){bone(A.shoulderNear,A.elbowOff);bone(A.elbowOff,A.handOff);p.P(A.handOff.x+1,A.handOff.y+1,B);p.P(A.handOff.x-1,A.handOff.y+1,B);}
  const hd=A.head;p.ell(hd.x+1,hd.y-1,6,6,B);p.R(hd.x-1,hd.y+4,8,3,B);                    // skull + jaw
  p.R(A.eyeFar.x-1,A.eyeFar.y-1,3,3,HOLE);p.R(A.eyeNear.x-1,A.eyeNear.y-1,3,3,HOLE);p.P(A.nose.x-1,A.nose.y+1,HOLE);p.P(A.nose.x-2,A.nose.y+1,HOLE);
  p.R(A.mouth.x-3,A.mouth.y,7,1,HOLE);for(let x=A.mouth.x-3;x<=A.mouth.x+3;x+=2)p.P(x,A.mouth.y,B);p.P(hd.x-3,hd.y-4,BD);p.P(hd.x+3,hd.y-5,BD);
  return f.zap=c;}

// =============== MODULAR WEAPON (hi-res, attached to arm) ===============
// pivot (0,0) = far shoulder; +x points along the aim. The arm reaches across the chest to the grip at x=G.
const WG={w:230,h:96,px:34,py:58};
let weaponCache=null;
// bend = elbow offset in px (see gun arm below). WBENDS are the baked variants; WBEND0 = level aim (what getWeapon() returns).
const WBENDS=[-2,-1,0,1,2,3,4],WBEND0=1;
// weapon build context. spec=null -> the main build (globals). spec={ammo,frame,items:[]} -> any other weapon (e.g. off-hand slot).
function wctx(spec){if(!spec)return{cnt:CNT,ammo:build.ammo,frame:build.frame,guns:S.guns,rangeAdd:S.rangeAdd,width:D.width,shots:D.shots};
  const cnt={};(spec.items||[]).forEach(id=>cnt[id]=(cnt[id]||0)+1);let st={rangeAdd:0,width:10,widthPct:0,shots:1,guns:[]};
  try{if(typeof baseStats==='function'){st=baseStats();AMMO[spec.ammo||0].apply(st);FRAMES[spec.frame||0].apply(st);(spec.items||[]).forEach(id=>ITEMS.find(i=>i.id===id)?.apply(st));}}catch(e){}
  return{cnt,ammo:spec.ammo||0,frame:spec.frame||0,guns:[AMMO[spec.ammo||0].id].concat(st.guns||[]),rangeAdd:st.rangeAdd||0,width:(st.width||10)*(1+(st.widthPct||0)),shots:Math.min(9,st.shots||1)};}
// off=true: off-hand version (arm in shadow, heights pushed back behind the torso, pivot = near shoulder VG.ox,VG.oy)
function renderWeapon(bend=WBEND0,spec=null,off=false){
  const c=mkCanvas(WG.w,WG.h),g=c.getContext('2d'),Z=depthBuf(WG.w,WG.h),p=painter(g,WG.px,WG.py,Z),{R,P,box,ell,line,lift}=p;
  const X=wctx(spec),zo=off?-14:0,layer=(b2,pr)=>p.layer(b2+zo,pr);
  const n=id=>X.cnt[id]||0,ammo=AMMO[X.ammo],fr=FRAMES[X.frame].id,anims=[];
  const gold=n('greed')>0;
  const metal=gold?'#e8c030':'#9aa4ae',metalD=gold?'#a07a10':'#5f6872',metalL=gold?'#fff4b0':'#d4dce4';
  const dark=gold?'#8a6a10':'#3a4048',darkL=gold?'#c09a28':'#5a626c',wood='#7a4a28',woodD='#4e2e16',woodL='#a06a40',brass=gold?'#ffd24a':'#c99a3a';
  const sk=skinPal(),skin=sk.s,skinL=sk.L,skinD=sk.D;
  const cp=coatPal(),lvl=cp.lvl,coat=off?cp.M:cp.c,coatL=off?cp.c:cp.L,coatM=off?cp.D:cp.M,coatD=off?cp.DD:cp.D;
  const G=22; // arm length: shoulder -> grip
  const tops=[],bots=[],wraps=[];
  for(const it of ITEMS){const k=n(it.id);if(!k||!it.wv)continue;for(let i=0;i<Math.min(k,3);i++)(it.wv.s==='top'?tops:it.wv.s==='bot'?bots:wraps).push(it);}
  const sumW=a=>a.reduce((s,it)=>s+it.wv.w*2+2,0);
  const L0=G+{pistol:21,blunder:23,rifle:41,repeater:29}[fr];
  const extra=X.guns.slice(1);
  const L=Math.min(145,Math.max(L0+clamp(Math.round(X.rangeAdd/5),0,36),G+sumW(tops)+4,G+16+sumW(bots),G+16+sumW(wraps)));
  const F=clamp(Math.round(X.width/3),2,22);
  const h0=fr==='blunder'?3:fr==='repeater'?4:2;
  const topBase=-6-extra.length*6;
  const gunY=[0];
  function A2(o){anims.push(o);}
  // height bands (px): stock 18 < extra guns 20 < arm 24 < receiver/barrel 26-28 < modules 28-30 < hand 30
  const barrelP=Prof.cylH(0,h0+1,h0+1);

  // ---- stock (behind arm)
  if(fr==='rifle'){layer(18,Prof.cylH(.5,3.5,2));box(G-24,-3,22,7,wood);R(G-24,-3,22,1,woodL);R(G-22,1,18,1,woodD);layer(19,Prof.slab(G-26,-5,G-24,5,1.5,1));box(G-26,-5,3,11,dark);layer(18,null);R(G-18,-5,8,2,woodD);}
  else if(fr==='blunder'){layer(18,Prof.cylH(.5,3.5,2));box(G-14,-3,12,7,wood);R(G-14,-3,12,1,woodL);layer(19,Prof.slab(G-15,-4,G-14,4,1.5,1));box(G-15,-4,2,9,brass);}
  // ---- extra guns stacked on top
  extra.forEach((t,i)=>{const y=-9-i*6;gunY.push(y);
    layer(20,Prof.cylH(y,2.5,2));box(G+2,y-2,L-G-6,4,metalD);R(G+2,y-2,L-G-6,1,metalL);R(G+8,y+2,2,3,dark);R(L-10,y+2,2,3,dark);
    layer(21,Prof.slab(G-1,y-3,G+3,y+2,1.5,1));box(G-1,y-3,5,6,dark);layer(20,Prof.cylH(y,2.5,2));
    if(t==='laser'){R(G+6,y-2,L-G-12,1,'#ff6a6a');box(L-4,y-3,3,6,dark);P(L-2,y,'#ff4a4a');A2({k:'led',x:L-1,y:y,c:'#ff4a4a'});}
    else if(t==='bullet'){box(L-4,y-2,4,4,dark);R(L-3,y-1,1,2,'#111');box(G+4,y+2,3,5,'#2a2e33');P(G+5,y+2,'#ffd76a');}
    else{A2({k:'saw',x:L+3,y:y,r:4});}});

  // ---- gun arm (sleeve from the far shoulder across the chest down to the grip) — frontmost body part
  layer(24,Prof.dome(0,0,3,3,3));ell(0,0,3,3,coat);R(-2,-3,4,1,coatL);R(-3,1,1,2,coatD);P(1,-2,coatL);
  // two segments: shoulder -> elbow -> grip. `bend` pushes the elbow off the straight line
  // (+ = elbow sags below the arm line, - = elbow kicks up), grip and gun stay put.
  const elb=Math.round(G*.45),ey=Math.round(3*elb/(G-2))+bend,ax=G-2,ay=3;
  const armY=x=>x<=elb?ey*x/elb:ey+(ay-ey)*(x-elb)/(ax-elb);
  for(let x=0;x<=ax;x++){const y=Math.round(armY(x)),th=x<elb?6:5,top=y-3+(6-th);
    layer(24,x<=elb?Prof.cap(0,0,elb,ey,3,2.8):Prof.cap(elb,ey,ax,ay,2.5,2.8));
    R(x,top,1,th,coat);P(x,top,coatL);if(x%6!==3)P(x,top+1,coatL);P(x,top+th-2,coatM);P(x,top+th-1,coatD);}
  // elbow joint: round it off and put the crease on the inside of the bend
  layer(24.5,Prof.dome(elb,ey,3,3,2.8));ell(elb,ey,2,2,coat);P(elb-1,ey-2,coatL);P(elb,ey+2,coatM);P(elb+1,ey+2,coatD);
  if(bend>=1){P(elb,ey-2,coatD);P(elb+1,ey-2,coatM);P(elb-1,ey-1,coatM);}
  else if(bend<=-1){P(elb,ey+1,coatD);P(elb+1,ey+1,coatD);P(elb-1,ey+1,coatM);}
  else{R(elb,ey-2,1,4,coatD);P(elb+1,ey+1,coatM);}
  layer(25,Prof.cylV(G-2.5,1.5,1.5));R(G-4,0,3,6,coatM);R(G-4,0,3,1,coatL);R(G-2,1,1,5,coatD);      // cuff
  if(n('virus')){layer(25,Prof.slab(7,-2,10,1,1,1));box(7,-2,4,4,'#c8e030');P(8,-1,'#222');P(9,0,'#222');P(7,-2,'#f0ff80');}
  if(lvl>=2){layer(26,Prof.dome(0,-1,4,3,2.5));ell(0,-1,4,3,'#6a7282');R(-2,-3,4,1,'#9aa2b2');P(-1,-3,'#aab');P(2,-3,'#aab');}
  if(n('cryo')||n('zero')){layer(27,null);R(-1,-6,1,4,'#bff4ff');R(0,-5,1,3,'#e8ffff');R(1,-4,1,2,'#9ad8f0');}
  // ---- receiver / barrel by frame
  if(fr==='pistol'){
    layer(26,Prof.slab(G-3,-5,G+11,3,2.5,2));box(G-3,-5,15,9,dark);for(let i=0;i<3;i++)R(G+i*2,-3,1,3,darkL);layer(27,Prof.dome(G-4,-5,1,1,1));box(G-5,-6,3,3,dark);
    layer(27,barrelP);box(G+12,-h0-1,L-G-12,2*h0+1,metal);R(G+12,-h0-1,L-G-12,1,metalL);R(G+12,h0,L-G-12,1,metalD);R(G+12,-h0,L-G-12,1,shade(metal,.15));
  }else if(fr==='blunder'){
    layer(26,Prof.slab(G-3,-5,G+11,4,2.5,2));box(G-3,-5,15,10,brass);lift(.4);P(G-1,-3,'#7a5a18');P(G+9,-3,'#7a5a18');P(G-1,2,'#7a5a18');P(G+9,2,'#7a5a18');
    layer(27,Prof.cylH(.5,h0+1,h0+1));box(G+12,-h0-1,L-G-12,2*h0+2,brass);R(G+12,-h0-1,L-G-12,1,'#fff0b0');
    for(let x=G+16;x<L-2;x+=8){lift(.7);box(x,-h0-2,2,2*h0+4,shade(brass,-.3));lift(0);}
  }else if(fr==='rifle'){
    layer(26,Prof.slab(G-3,-5,G+13,3,2.5,2));box(G-3,-5,17,9,dark);R(G+5,-6,5,1,'#c0c8d0');layer(28,Prof.dome(G+10,-7.5,1,1.5,1));box(G+9,-9,2,3,'#c0c8d0');
    layer(27,barrelP);box(G+14,-h0,L-G-14,2*h0+1,metal);R(G+14,-h0,L-G-14,1,metalL);
    layer(28,Prof.cylH(-.5,4,2));box(G+14,-4,16,8,woodD);R(G+14,-4,16,1,'#7a4a28');for(let x=G+16;x<G+28;x+=3)P(x,0,'#3a2010');
    layer(28,Prof.slab(L-6,-h0-1,L-5,h0+1,1,1));box(L-6,-h0-1,2,2*h0+3,dark);
  }else{ // repeater
    layer(26,Prof.slab(G-4,-6,G+8,5,2.5,2));box(G-4,-6,13,12,dark);R(G-2,-4,9,1,darkL);layer(27,Prof.dome(G+3,8,5,3,2.5));ell(G+3,8,5,3,darkL);R(G,8,6,1,'#2a3038');P(G+1,6,'#7a848e');
    for(const y of[-4,-1,2]){layer(27,Prof.cylH(y+.5,1,1.2));R(G+9,y,L-G-9,2,metal);R(G+9,y,L-G-9,1,metalL);}
    layer(28,Prof.cylH(-.5,6,2));box(G+13,-6,2,11,dark);box(L-7,-6,2,11,dark);layer(26,null);box(G-7,-2,3,2,'#888');R(G-8,-4,1,6,'#888');
    A2({k:'gat',x:G+9,y:-4,w:L-G-9});
  }
  // ---- grip + trigger
  layer(25,Prof.slab(G-3,4,G+5,13,1.8,2));
  for(let i=0;i<10;i++){R(G-Math.floor(i/4),4+i,6,1,i%3===0?woodD:wood);P(G-Math.floor(i/4)+4,4+i,woodL);}R(G-2,13,6,1,woodD);
  layer(26,null);R(G+5,4,5,1,dark);R(G+9,4,1,5,dark);R(G+5,8,5,1,dark);R(G+6,5,1,2,'#aaa');
  // ---- ammo-type hardware
  if(ammo.id==='laser'){
    layer(27,Prof.slab(G,-6,G+7,4,2.5,2));lift(.6);R(G+1,-6,1,11,'#ff4a4a');R(G+4,-6,1,11,'#ff4a4a');R(G+7,-6,1,11,'#ff4a4a');
    layer(27,barrelP);lift(.3);R(G+13,-h0-1,Math.max(2,L-G-16),1,'#ff7a7a');A2({k:'pulse',x:G+4,y:-1,r:3,c:'#ff4a4a',a:.25});
  }else if(ammo.id==='bullet'){
    layer(27,Prof.slab(G+3,4,G+9,13,1.8,1.5));for(let i=0;i<10;i++)R(G+3+Math.floor(i/3),4+i,5,1,'#2a2e33');R(G+4,4,3,1,'#ffd76a');R(G+4,5,3,1,'#c9a227');
    layer(27,null);R(G+3,-4,5,2,'#161a1e');P(G+4,-4,'#ffd76a');
  }else{
    layer(27,Prof.slab(G-2,-12,G+9,-6,2,2));box(G-2,-12,12,7,'#5a626c');R(G-1,-13,10,1,'#dfe6ec');R(G,-11,8,1,'#aab4be');R(G,-9,8,1,'#aab4be');R(G+3,-6,4,1,'#111');
  }
  // ---- hand on the grip: knuckles wrap the front, thumb over the top
  layer(30,Prof.dome(G+1.5,4,3.5,3,2.5));
  box(G-1,2,6,5,skin);R(G-1,2,6,1,skinL);R(G+4,3,1,3,skinD);R(G,6,4,1,skinD);
  P(G+1,4,skinD);P(G+3,4,skinD);P(G+1,5,skinD);P(G+3,5,skinD);         // finger gaps
  layer(31,Prof.dome(G-1,1.5,1.5,1,1.5));R(G-2,1,3,2,skin);P(G-2,1,skinL);P(G,2,skinD);   // thumb
  if(sk.mut){P(G+1,3,'#bff08a');}

  // ---- wrap modules along the barrel
  let wx=G+15;
  for(const it of wraps){const x=wx,ww=it.wv.w*2;layer(28,Prof.cylH(0,7,3));
    if(it.id==='fins'){for(const fx of[x,x+2]){R(fx,-7,1,14,'#c0c8d0');P(fx,-7,'#fff');P(fx,6,'#7a848e');}R(x+1,-7,1,14,'#6a747e');}
    else if(it.id==='cryo'){layer(28,Prof.cylH(0,5,2.5));for(let y=-4;y<=4;y+=2)R(x+(((y+4)/2)%2),y,3,1,'#8ff0ff');R(x,-5,4,1,'#e8ffff');A2({k:'mist',x:x+2,y:0});}
    else if(it.id==='sustain'){for(const rx of[x,x+4]){box(rx,-6,3,12,'#7a1818');R(rx+1,-6,1,12,'#ff4a4a');P(rx+1,-6,'#ffd0d0');}R(x+3,-1,1,2,'#ff4a4a');A2({k:'pulse',x:x+4,y:0,r:4,c:'#ff4a4a',a:.25});}
    else if(it.id==='zero'){layer(28,Prof.cylH(0,5,2.5));R(x,-4,4,1,'#e8ffff');R(x+1,-5,2,1,'#ffffff');R(x,4,1,3,'#bff4ff');R(x+2,4,1,2,'#bff4ff');R(x+3,4,1,4,'#9ad8f0');A2({k:'mist',x:x+2,y:3});}
    wx+=ww+2;}
  // ---- top modules (each gets a rounded height bump)
  let tx=G-2;const tb=topBase;
  for(const it of tops){const x=tx,ww=it.wv.w*2;layer(28,Prof.dome(x+ww/2,tb-6,ww/2+1,7,3));
    switch(it.id){
      case'scope':layer(28,Prof.cylH(tb-3.5,2.5,2.5));box(x,tb-6,12,5,'#2a2e33');R(x+1,tb-5,10,1,'#4a4e54');box(x+12,tb-7,2,7,'#3a4048');lift(.5);R(x+13,tb-6,1,5,'#7ad0ff');P(x+13,tb-6,'#e8f8ff');lift(0);
        box(x-1,tb-5,1,3,'#555');R(x+2,tb-1,2,1,dark);R(x+8,tb-1,2,1,dark);box(x+5,tb-9,2,3,'#555');break;
      case'acid':layer(28,Prof.cylV(x+2.5,3,2.5));box(x,tb-9,6,9,'#a8b020');R(x+1,tb-7,3,4,'#f0ff60');P(x+1,tb-7,'#ffffc0');R(x,tb-3,6,1,'#222');P(x+1,tb-3,'#ffd23c');P(x+3,tb-3,'#ffd23c');
        box(x+1,tb-10,4,1,'#777');R(x+6,tb-5,2,1,'#777');A2({k:'bubble',x:x+1,y:tb-7,w:3,h:4,c:'#ffffc0'});break;
      case'poison':layer(28,Prof.cylV(x+1.5,2,2));box(x,tb-8,4,8,'#2aa82a');R(x+1,tb-7,1,6,'#9affa0');R(x+1,tb-10,2,2,'#cde');R(x+1,tb-11,2,1,'#a07040');R(x+1,tb-5,2,2,'#f0f0f0');P(x+1,tb-4,'#222');
        A2({k:'bubble',x:x,y:tb-8,w:4,h:7,c:'#d0ffd0'});break;
      case'tesla':layer(28,Prof.cylV(x+1.5,1,1));R(x+1,tb-11,2,11,'#8a8a92');layer(29,Prof.cylV(x+1.5,2,1.5));for(const y of[-9,-7,-5,-3])R(x,tb+y,4,1,'#c97a3a');layer(29,Prof.dome(x+2,tb-13,2,2,2));ell(x+2,tb-13,2,2,'#fff36b');P(x+1,tb-14,'#ffffff');A2({k:'spark',x:x+2,y:tb-13});break;
      case'hypno':R(x+3,tb-2,2,2,dark);layer(29,Prof.dome(x+4,tb-6,4,4,2));ell(x+4,tb-6,4,4,'#7a20b0');A2({k:'hypno',x:x+4,y:tb-6,r:4});break;
      case'clock':R(x,tb-3,8,3,'#c8302a');R(x,tb-2,8,1,'#a02018');R(x+2,tb-3,1,3,'#222');R(x+5,tb-3,1,3,'#222');
        layer(29,Prof.dome(x+4,tb-7,3,3,2));ell(x+4,tb-7,3,3,'#c33');ell(x+4,tb-7,2,2,'#f4f4f4');layer(29,Prof.dome(x+1,tb-11,1,1,1));ell(x+1,tb-11,1,1,'#c33');layer(29,Prof.dome(x+7,tb-11,1,1,1));ell(x+7,tb-11,1,1,'#c33');A2({k:'clock',x:x+4,y:tb-7});break;
      case'remote':box(x,tb-4,4,4,'#333');P(x+1,tb-3,'#3f3');layer(28,null);R(x+1,tb-14,1,10,'#8a8a92');A2({k:'led',x:x+1,y:tb-15,c:'#ff3030'});break;
      case'syringe':layer(28,Prof.cylH(tb-3.5,2,2));box(x,tb-5,10,4,'#e8e8f0');R(x+1,tb-4,6,2,'#c01828');P(x+1,tb-4,'#ff6070');R(x-3,tb-4,3,2,'#999');R(x-4,tb-6,1,6,'#999');
        R(x+10,tb-4,1,2,'#bbb');R(x+11,tb-3,4,1,'#ddd');R(x+3,tb-1,1,2,'#c01828');A2({k:'bubble',x:x+1,y:tb-4,w:6,h:2,c:'#ff9aa0'});break;
      case'hive':R(x+3,tb-8,2,8,'#8a8a92');layer(29,Prof.dome(x+4,tb-11,4,4,3));g.globalAlpha=.4;ell(x+4,tb-11,4,4,'#a8dcff');g.globalAlpha=1;ell(x+4,tb-11,3,2,'#ff8fb0');P(x+3,tb-12,'#d0607e');P(x+5,tb-11,'#d0607e');
        A2({k:'pulse',x:x+4,y:tb-11,r:3,c:'#ff8fb0',a:.3});break;
      case'storm':layer(28,Prof.cylV(x+.5,1,1));R(x,tb-13,2,13,'#9a9aa4');layer(28,Prof.cylV(x+6.5,1,1));R(x+6,tb-13,2,13,'#9a9aa4');layer(29,null);ell(x+1,tb-14,1,1,'#fff36b');ell(x+7,tb-14,1,1,'#fff36b');layer(28,null);R(x,tb-2,8,2,dark);
        A2({k:'arc',x:x+1,y:tb-14,x2:x+7,y2:tb-14});break;
      case'nuke':layer(28,Prof.cylH(tb-3,3,2.5));box(x,tb-6,8,6,'#ffd23c');R(x+8,tb-5,2,4,'#ffd23c');R(x+10,tb-4,1,2,'#e8b020');R(x-2,tb-7,2,2,'#8a8a92');R(x-2,tb-1,2,1,'#8a8a92');
        lift(.3);P(x+4,tb-3,'#222');P(x+3,tb-4,'#222');P(x+5,tb-4,'#222');P(x+4,tb-2,'#222');R(x+1,tb-6,6,1,'#fff0a0');lift(0);break;
      case'moon':layer(29,Prof.cylH(tb-9,1.5,1.5));R(x,tb-10,10,1,'#f0f0f8');R(x+1,tb-9,8,1,'#c8c8d0');R(x+2,tb-8,6,1,'#a8a8b0');layer(28,null);R(x+4,tb-14,2,4,'#8a8a92');R(x+4,tb-7,2,7,'#777');
        A2({k:'led',x:x+5,y:tb-15,c:'#ff3030'});break;
    }
    tx+=ww+2;}
  // ---- bottom modules
  let bx=G+15;const bb=h0+2;
  for(const it of bots){const x=bx,ww=it.wv.w*2;layer(27,Prof.dome(x+ww/2,bb+3,ww/2+1,4,2.5));
    switch(it.id){
      case'cell':box(x,bb,8,4,'#2a8ad0');R(x+2,bb+1,4,2,'#9ff');R(x+1,bb-1,1,1,dark);R(x+6,bb-1,1,1,dark);A2({k:'pulse',x:x+4,y:bb+2,r:2,c:'#6ff',a:.3});break;
      case'thermite':layer(27,Prof.cylH(bb+2.5,3,2.5));box(x,bb,10,6,'#e06a1a');R(x+2,bb,1,6,'#ffb050');R(x+6,bb,1,6,'#ffb050');R(x+10,bb+2,2,2,'#777');R(x+1,bb-1,2,1,dark);A2({k:'flame',x:x+12,y:bb+3,side:1});break;
      case'bleed':R(x,bb,10,2,'#ccd4dc');R(x,bb,10,1,'#f0f4f8');for(let i=0;i<10;i+=2)P(x+i,bb+2,'#ccd4dc');R(x+1,bb-1,2,1,dark);P(x+3,bb+2,'#a01020');P(x+3,bb+3,'#a01020');break;
      case'virus':layer(27,Prof.cylH(bb+3,3.5,2.5));box(x,bb,8,7,'#9acd32');R(x,bb+1,8,1,'#6a9a12');R(x,bb+5,8,1,'#6a9a12');R(x+3,bb+2,2,2,'#222');P(x+2,bb+3,'#222');P(x+5,bb+3,'#222');A2({k:'bubble',x:x,y:bb+7,w:8,h:3,c:'#c8f060'});break;
      case'grenade':box(x,bb,8,4,'#4a5a3a');R(x+1,bb+1,6,1,'#2a3a1a');layer(28,Prof.dome(x+10,bb+2,2,2,2));ell(x+10,bb+2,2,2,'#4a6a2a');P(x+9,bb+1,'#6a8a3a');R(x+10,bb-1,2,1,'#ccc');break;
      case'auto':for(let i=0;i<10;i++){const yy=bb+(i%3===0?2:1)+Math.round(Math.sin(i*.8));layer(27,Prof.cylH(yy+1,1.5,1.5));R(x+i,yy,1,3,'#c9a227');P(x+i,yy+3,'#ffd76a');}break;
      case'disint':layer(28,Prof.dome(x+3,bb+2.5,3,3,2.5));R(x+2,bb,2,1,'#ff2a2a');R(x+1,bb+1,4,1,'#ff2a2a');R(x,bb+2,6,2,'#ff2a2a');R(x+1,bb+4,4,1,'#c01010');R(x+2,bb+5,2,1,'#a01010');P(x+2,bb+1,'#ffb0b0');P(x+1,bb+2,'#ffd0d0');
        A2({k:'pulse',x:x+3,y:bb+3,r:3,c:'#ff2a2a',a:.3});break;
      case'reactor':box(x,bb,10,7,'#2a3a2a');layer(28,Prof.dome(x+5,bb+3,2,2,1.5));ell(x+5,bb+3,2,2,'#7dff3a');P(x+5,bb+3,'#e8ffe0');layer(27,null);R(x,bb+6,10,1,'#ffd23c');A2({k:'pulse',x:x+5,y:bb+3,r:3,c:'#7dff3a',a:.35});break;
      case'singular':box(x,bb,8,8,'#333');lift(-1);R(x+1,bb+1,6,6,'#110018');lift(0);A2({k:'sing',x:x+4,y:bb+4,small:1});break;
    }
    bx+=ww+2;}
  // ---- muzzle: width cone (flared bell with Flared Muzzle), nozzles (shots), saw, drill
  layer(27,Prof.cylH(0,Math.max(F,h0+1)+.5,2.5));
  if(F>h0+1){for(let i=0;i<6;i++){const hh=h0+Math.round((F-h0)*(i+1)/6);R(L+i,-hh,1,2*hh+1,i===5?metalL:(fr==='blunder'?brass:metalD));P(L+i,-hh,metalL);P(L+i,hh,shade(metalD,-.3));}
    if(n('flare')){R(L+5,-F-1,1,2*F+3,brass);P(L+5,-F-1,'#fff0b0');}}
  else{box(L,-h0-1,4,2*h0+3,dark);if(n('flare')){R(L+3,-h0-2,1,2*h0+5,brass);}}
  const mx=F>h0+1?L+6:L+4,sh=X.shots;
  layer(28,null);
  for(let i=0;i<sh;i++){const y=sh>1?Math.round(-(F-1)+2*(F-1)*i/(sh-1)):0;R(mx,y-1,2,3,dark);P(mx+1,y,ammo.col);}
  let muz=mx+2;
  if(ammo.id==='razor'){layer(28,Prof.dome(mx+7,0,6,6,2));ell(mx+7,0,6,6,'#8a949e');A2({k:'saw',x:mx+7,y:0,r:6});muz=mx+13;}
  if(n('drill')){const x0=muz;layer(28,Prof.cylH(0,3,2.5));for(let i=0;i<9;i++){const hh=Math.max(0,Math.round(3-i/3));R(x0+i,-hh,1,2*hh+1,'#c8ccd2');P(x0+i,-hh,'#eef0f4');}A2({k:'drill',x:x0,y:0,len:9});muz=x0+9;}
  anims.push({k:'muzzle',x:muz,y:0});
  const anchors={shoulder:{x:0,y:0},elbow:{x:elb,y:ey},grip:{x:G+1,y:4},trigger:{x:G+7,y:6},stock:{x:G-14,y:0},
    railTop:{x:G-2,y:topBase},railBottom:{x:G+15,y:h0+2},wrap:{x:G+15,y:0},barrelEnd:{x:L,y:0},muzzle:{x:muz,y:0}};
  return{cv:selOutline(c),depth:padDepth(Z),muz,anims,gunY,anchors,bend,off};
}
function getWeapon(){if(!weaponCache){weaponCache=renderWeapon(WBEND0);weaponCache.bent={[WBEND0]:weaponCache};}return weaponCache;}
// same weapon with a different elbow bend (grip, muzzle and gunY are identical across bends)
function getWeaponBent(b){const w=getWeapon();return w.bent[b]||(w.bent[b]=renderWeapon(b));}
// off-hand weapon (second slot). spec=null mirrors the main build; cached per spec+bend, reset with weaponCache.
function getOffWeapon(spec,b=WBEND0){const w=getWeapon(),m=w.offs||(w.offs={}),key=JSON.stringify(spec||null)+'|'+b;return m[key]||(m[key]=renderWeapon(b,spec,true));}
// elbow bend from the aim angle: level = slight sag, aiming up = arm folds (elbow drops), aiming down = elbow kicks out
function bendForAim(aim){const up=-Math.sin(aim);return clamp(Math.round(WBEND0+(up>0?3*up:2*up)),WBENDS[0],WBENDS[WBENDS.length-1]);}

// ---------- live animated overlays ----------
function animPart(p,a,o,t){
  const g=p.g,R=p.R,P=p.P;
  switch(a.k){
    case'tank':for(let i=0;i<4;i++){const yy=a.y+a.h-1-Math.floor((t*9+i*3.7)%a.h);P(a.x+((i*4+Math.floor(t*2+i))%a.w),yy,a.c);}break;
    case'jar':for(let i=0;i<3;i++){const yy=a.y+a.h-1-Math.floor((t*6+i*5.3)%a.h);P(a.x+((i*5+3)%a.w),yy,'#f0ffff');}break;
    case'bubble':if(Math.random()<.35)P(a.x+Math.floor(Math.random()*a.w),a.y+Math.floor(Math.random()*a.h),a.c);break;
    case'wheel':{const sp=t*(o.moving?16:5);p.ring(a.x,a.y,a.r,'#b8bcc4');p.ring(a.x,a.y,a.r-1,'#7a7e86');
      for(let i=0;i<6;i++){const an=sp/2+i*1.047;p.line(a.x,a.y,Math.round(a.x+Math.cos(an)*(a.r-2)),Math.round(a.y+Math.sin(an)*(a.r-2)),'#6a6e76');}
      R(a.x-1,a.y-1,3,3,'#555');const hx=a.x-3,hy=a.y+a.r-6,st=Math.floor(sp*1.5)%2;
      p.ell(hx+3,hy+2,3,2,'#c8884a');R(hx+5,hy,2,2,'#c8884a');P(hx+6,hy,'#111');P(hx+7,hy+1,'#ff9aa0');R(hx+1,hy+1,3,1,'#f0e0c0');
      P(hx+1+st*2,hy+4,'#ffb0b0');P(hx+4-st*2,hy+4,'#ffb0b0');P(hx,hy+1+st,'#ff9aa0');break;}
    case'spark':if(Math.random()<.4){for(let i=0;i<3;i++)P(a.x+Math.round((Math.random()-.5)*5),a.y+Math.round((Math.random()-.5)*5),Math.random()<.5?(a.c||'#fff36b'):'#fff');}break;
    case'led':if(Math.sin(t*6+a.x*.7)>0){g.globalAlpha=.35;R(a.x-1,a.y-1,3,3,a.c);g.globalAlpha=1;P(a.x,a.y,'#fff');}else P(a.x,a.y,shade(a.c,-.5));break;
    case'flame':{const h=2+Math.floor(Math.random()*3);if(a.side){R(a.x,a.y,h,1,'#ff7a2a');P(a.x+h,a.y,'#ffd23c');}else{R(a.x,a.y-h,1,h,'#ff7a2a');P(a.x,a.y-h-1,'#ffd23c');if(Math.random()<.5)P(a.x+(Math.random()<.5?-1:1),a.y-1,'#ff4a1a');}break;}
    case'pulse':{const s=.5+.5*Math.sin(t*5+a.x);g.globalAlpha=(a.a||.3)*(.5+s);p.ell(a.x,a.y,a.r+1,a.r+1,a.c);g.globalAlpha=1;break;}
    case'sing':{const yy=a.y+(a.small?0:Math.round(Math.sin(t*2)*2)),r=a.small?3:5;g.globalAlpha=.45;p.ell(a.x,yy,r,r,'#5a20a0');g.globalAlpha=1;p.ell(a.x,yy,r-2,r-2,'#000');
      for(let i=0;i<5;i++){const an=t*4+i*1.256;P(Math.round(a.x+Math.cos(an)*r),Math.round(yy+Math.sin(an)*r*.6),'#c890ff');}break;}
    case'arc':if(Math.random()<.6){let px=a.x,py=a.y;const n=6;for(let i=1;i<=n;i++){const nx=Math.round(a.x+(a.x2-a.x)*i/n),ny=Math.round(a.y+(a.y2-a.y)*i/n+(i<n?(Math.random()-.5)*4:0));p.line(px,py,nx,ny,'#fff36b');px=nx;py=ny;}}break;
    case'mist':if(Math.random()<.4)P(a.x+Math.round((Math.random()-.3)*6),a.y+Math.round((Math.random()-.5)*6),'#e8ffff');break;
    case'clock':{const an=t*2.5;p.line(a.x,a.y,Math.round(a.x+Math.cos(an)*2),Math.round(a.y+Math.sin(an)*2),'#222');break;}
    case'hypno':{p.ell(a.x,a.y,a.r,a.r,'#7a20b0');for(let s=0;s<16;s++){const an=-t*7+s*.85,rr=s/16*a.r;P(Math.round(a.x+Math.cos(an)*rr),Math.round(a.y+Math.sin(an)*rr),'#f0c8ff');}P(a.x,a.y,'#fff');break;}
    case'saw':{const rot=t*(o.firing?28:6),r=a.r;p.ell(a.x,a.y,r,r,'#c8d0d8');p.ell(a.x,a.y,r-2,r-2,'#8a949e');
      for(let i=0;i<8;i++){const an=rot+i*.785;P(Math.round(a.x+Math.cos(an)*(r+1)),Math.round(a.y+Math.sin(an)*(r+1)),'#f0f4f8');P(Math.round(a.x+Math.cos(an+.3)*(r-1)),Math.round(a.y+Math.sin(an+.3)*(r-1)),'#5a646e');}
      R(a.x-1,a.y-1,2,2,'#333');break;}
    case'drill':{const off=Math.floor(t*(o.firing?40:8));for(let i=0;i<a.len;i++){const hh=Math.max(0,Math.round(3-i/3));if((i+off)%3===0)R(a.x+i,a.y-hh,1,2*hh+1,'#6a7078');}break;}
    case'gat':{if(o.firing){const ph=Math.floor(t*30)%3;for(let i=0;i<3;i++)R(a.x,a.y+i*3,a.w,1,i===ph?'#ffffff':'#7a848e');}break;}
    case'tscope':{ // telescoping eyepiece: slides out while firing/aiming, tucks back at rest, occasional lens glint
      const ext=o.firing||(o.recoil||0)>0?6:(Math.sin(t*1.7+1)>.97?2:0);
      if(ext>0){const x2=a.x,l2=2+ext,x3=x2+l2,l3=1+Math.round(ext*.6);
        R(x2,a.y-1,l2,3,'#9aa4ae');R(x2,a.y-1,l2,1,'#d4dce4');R(x2,a.y+1,l2,1,'#5f6872');R(x2+l2-1,a.y-2,1,5,'#8a6a18');P(x2+l2-1,a.y-2,'#ffe08a');  // steel tube + collar
        R(x3,a.y-1,l3,3,'#c9a227');R(x3,a.y-1,l3,1,'#ffe08a');R(x3,a.y+1,l3,1,'#8a6a18');                                                          // brass tube
        R(x3+l3,a.y-2,1,5,'#5f6872');R(x3+l3+1,a.y-1,1,3,'#9ccbe0');P(x3+l3+1,a.y-1,'#ffffff');}                                                  // lens ring + lens
      const tip=a.x+(ext>0?2+ext+1+Math.round(ext*.6)+1:3);if(Math.sin(t*2.3+a.x)>.93){P(tip,a.y-1,'#ffffff');P(tip+1,a.y-2,'#ffffff');P(tip+1,a.y,'#e8f8ff');}
      break;}
    case'glint':{const ph=(t*.6+a.x*.03)%1;if(ph<.12){const k=Math.floor(ph/.12*5);P(a.x+k,a.y+k,'#ffffff');P(a.x+k+1,a.y+k,'#e8f8ff');}break;}
    case'muzzle':if(o.flash>0){const col=AMMO[build.ammo].col,m=a.x;R(m,-2,5,5,col);R(m+5,-1,5,3,'#fff');R(m+1,-5,2,11,col);R(m-1,-1,3,3,'#fff');
      if(Math.random()<.5){R(m+3,-4,2,1,'#fff');R(m+3,4,2,1,'#fff');}}break;
  }
}
// manic face while firing: wide eyes, raised brows, open shouting mouth (head coords)
function drawShout(p,t){const sk=skinPal(),hairC=(CNT.zero||0)>0?'#c8ecff':'#a8a8c0',n=id=>CNT[id]||0;
  p.R(27,11,10,3,sk.s);p.R(27,13,1,1,sk.D);                       // clear the scowl
  p.R(27,11,4,1,hairC);p.R(33,10,4,1,hairC);p.P(27,12,hairC);p.P(36,11,hairC); // brows shoot up
  const jit=Math.floor(t*24)%2;
  p.R(28,13,4,5,sk.D);p.R(29,14,3,3,'#f4f0e8');p.P(30+jit,15,'#1c1214');
  if(!n('disint')&&!n('telescope')){p.R(32,13,5,5,sk.D);p.R(33,14,3,3,'#f4f0e8');p.P(34+jit,15,'#1c1214');}
  p.R(30,19,7,5,'#3a1010');p.R(31,19,5,1,'#f0ece0');p.R(31,23,5,1,'#e0dccc');p.R(32,21,3,2,'#c84a5a');p.P(33,20,'#5a1818');
}
// draw the full villain (sprite + overlays + aiming arm/weapon).
// o: {face,pose,aim,k,moving,firing,recoil,flash,white(hurt),zap(tazed),t,
//     off:{spec,aim,firing,recoil,flash}  -> second weapon in the off hand (LT), drawn behind the torso}
function kickOf(o){return(o.recoil||0)>.55||o.white||o.zap?-1:0;}
function drawArmBones(g,w){const p=painter(g),A=w.anchors;p.line(0,0,A.elbow.x,A.elbow.y,'#f6fbff',2);p.line(A.elbow.x,A.elbow.y,A.grip.x,A.grip.y,'#f6fbff',2);
  p.R(A.grip.x-1,A.grip.y-2,4,1,'#f6fbff');p.R(A.grip.x-1,A.grip.y,4,1,'#f6fbff');}
function drawWeaponAt(g,sx,sy,k,aim,w,anims,o,t,zapOn){
  g.save();g.translate(sx,sy);g.rotate(aim);if(Math.cos(aim)<0)g.scale(1,-1);g.scale(k,k);g.translate(-Math.round((o.recoil||0)*3),0);
  let im=w.cv;
  if(zapOn)im=w.zapImg||(w.zapImg=tint(w.cv,'#3a68ff',.75));
  else if(o.white&&Math.floor(t*20)%2===0)im=w.white||(w.white=tint(w.cv,'#ffffff',.85));
  g.drawImage(im,-WG.px-1,-WG.py-1);if(zapOn)drawArmBones(g,w);
  const pp=painter(g);for(const a of anims)animPart(pp,a,o,t);g.restore();}
function drawVillainAt(g,x,y,o){
  const k=o.k||1,face=o.face||1,t=o.t!==undefined?o.t:performance.now()/1000,armed=!!o.off,fr=getVillainFrames(armed)[o.pose||0],wp=getWeapon(),aim=o.aim||0;
  const kick=kickOf(o),zapOn=!!o.zap&&Math.floor(t*14)%2===0;
  // second weapon (off hand) first: it sits behind the torso
  let off=null;
  if(o.off){const oa=o.off.aim!==undefined?o.off.aim:aim,ow=getOffWeapon(o.off.spec||null,bendForAim(oa));
    const osx=x+(VG.ox+fr.lean+kick-VG.cx)*face*k,osy=y+(VG.oy-VG.cy+fr.bob)*k,oo=Object.assign({},o,{firing:o.off.firing,recoil:o.off.recoil,flash:o.off.flash});
    drawWeaponAt(g,osx,osy,k,oa,ow,ow.anims,oo,t,zapOn);off={sx:osx,sy:osy};}
  g.save();g.translate(x,y);g.scale(face*k,k);g.translate(-VG.cx+kick,-VG.cy);
  const p=painter(g);
  // glowing orb in the off hand (ammo colour) - drawn BEFORE the body so the coat hides it when the hand swings behind
  if(!armed){const h=fr.hand,col=AMMO[build.ammo].col,pu=1+.2*Math.sin(t*8)+(o.firing?.35:0);
    g.globalAlpha=.22;p.ell(h.x,h.y+1,Math.round(4*pu),Math.round(4*pu),col);g.globalAlpha=.7;p.ell(h.x,h.y+1,2,2,col);g.globalAlpha=1;
    p.R(h.x,h.y+1,2,2,'#fff');const oa=t*5;p.P(Math.round(h.x+Math.cos(oa)*4),Math.round(h.y+1+Math.sin(oa)*3),'#fff');}
  // rocket boot jets
  if(CNT.boots){for(const f of fr.feet){const L=o.moving?3+Math.floor(Math.random()*5):1+Math.floor(Math.random()*2);
    p.R(f.x-1,f.y+1,3,L,'#ff7a20');p.R(f.x,f.y+1,1,L+1,'#ffd23c');if(o.moving&&Math.random()<.5)p.P(f.x-2,f.y+L,'#ffb030');}}
  let img=fr.img;
  if(o.zap){const hf=hurtFrame(fr);img=zapOn?zapFrame(fr):(hf.yellow||(hf.yellow=tint(hf.img,'#fff36b',.45)));}
  else if(o.white){const hf=hurtFrame(fr),cyc=Math.floor(t*20)%3;img=cyc===0?(hf.white||(hf.white=tint(hf.img,'#ffffff',.85))):cyc===1?(hf.red||(hf.red=tint(hf.img,'#ff2020',.55))):hf.img;}
  g.drawImage(img,-1,-1);
  if(!zapOn)for(const a of fr.anims)animPart(p,a,o,t);
  if(o.firing&&!o.white&&!o.zap)drawShout(painter(g,fr.lean,fr.bob),t);
  if(o.zap){for(let i=0;i<3;i++)if(Math.random()<.7){const a0=fr.anchors[['head','chest','handOff','hip'][i]]||fr.anchors.head;  // electric crackle
    let px=a0.x,py=a0.y;for(let s2=0;s2<4;s2++){const nx=px+Math.round((Math.random()-.5)*10),ny=py+Math.round((Math.random()-.5)*10);p.line(px,py,nx,ny,Math.random()<.5?'#fff36b':'#bff4ff');px=nx;py=ny;}}}
  g.restore();
  // gun arm + main weapon (pivot = far shoulder), frontmost
  const sx=x+(VG.sx+fr.lean+kick-VG.cx)*face*k,sy=y+(VG.sy-VG.cy+fr.bob)*k;
  drawWeaponAt(g,sx,sy,k,aim,getWeaponBent(bendForAim(aim)),wp.anims,o,t,zapOn);
  return{sx,sy,off};
}
// world position of a point on the weapon (lx along barrel, ly perpendicular)
function weaponPoint(lx,ly){const fr=getVillainFrames()[P.pose||0],sx=P.x+(VG.sx+fr.lean-VG.cx)*P.face,sy=P.y+(VG.sy-VG.cy+fr.bob);
  const ca=Math.cos(P.aim),sa=Math.sin(P.aim),fy=ca<0?-1:1;return{x:sx+lx*ca-ly*fy*sa,y:sy+lx*sa+ly*fy*ca};}
// same for the off-hand weapon (pivot = near shoulder). aim2 = off-hand aim angle
function offWeaponPoint(lx,ly,aim2){const fr=getVillainFrames(true)[P.pose||0],sx=P.x+(VG.ox+fr.lean-VG.cx)*P.face,sy=P.y+(VG.oy-VG.cy+fr.bob);
  const ca=Math.cos(aim2),sa=Math.sin(aim2),fy=ca<0?-1:1;return{x:sx+lx*ca-ly*fy*sa,y:sy+lx*sa+ly*fy*ca};}
// ANCHOR API: world position of a named attach point for a villain drawn with drawVillainAt(g,x,y,o).
// Body: head helmet brow eyeFar eyeNear nose mouth ear neck chest belt hip back backpack shoulderFar shoulderNear
//       elbowOff handOff kneeFront kneeBack footFront footBack
// Weapon: 'gun.<name>' / 'off.<name>' with shoulder elbow grip trigger stock railTop railBottom wrap barrelEnd muzzle
function villainAnchor(name,x,y,o){const k=o.k||1,face=o.face||1,fr=getVillainFrames(!!o.off)[o.pose||0],kick=kickOf(o);
  if(name.startsWith('gun.')||name.startsWith('off.')){const isOff=name[0]==='o';if(isOff&&!o.off)return null;
    const a=isOff?(o.off.aim!==undefined?o.off.aim:o.aim||0):(o.aim||0),w=isOff?getOffWeapon(o.off.spec||null,bendForAim(a)):getWeaponBent(bendForAim(a)),q=w.anchors[name.slice(4)];if(!q)return null;
    const px=isOff?VG.ox:VG.sx,py=isOff?VG.oy:VG.sy,sx=x+(px+fr.lean+kick-VG.cx)*face*k,sy=y+(py-VG.cy+fr.bob)*k,rec=isOff?(o.off.recoil||0):(o.recoil||0);
    const lx=(q.x-Math.round(rec*3))*k,ly=q.y*k,ca=Math.cos(a),sa=Math.sin(a),fy=ca<0?-1:1;return{x:sx+lx*ca-ly*fy*sa,y:sy+lx*sa+ly*fy*ca};}
  const q=fr.anchors[name];if(!q)return null;return{x:x+(q.x-VG.cx+kick)*face*k,y:y+(q.y-VG.cy)*k};}

// =============== EXPORT HELPERS (sprite lab / Godot) ===============
// Albedo/height/normal sheets for every body pose (one row) and the weapon+arm canvas.
function villainSheets(armed=false){const fr=getVillainFrames(armed),fw=fr[0].img.width,fh=fr[0].img.height,mk=()=>mkCanvas(fw*fr.length,fh);
  const al=mk(),hm=mk(),nm=mk();fr.forEach((f,i)=>{const m=mapsOf(f);al.getContext('2d').drawImage(f.img,i*fw,0);hm.getContext('2d').drawImage(m.height,i*fw,0);nm.getContext('2d').drawImage(m.normal,i*fw,0);});
  return{albedo:al,height:hm,normal:nm,frameW:fw,frameH:fh};}
// weapon sheets: one row per elbow bend in WBENDS order (row WBENDS.indexOf(WBEND0) = level aim)
function weaponSheets(off=false){const vs=WBENDS.map(b=>off?getOffWeapon(null,b):getWeaponBent(b)),fw=vs[0].cv.width,fh=vs[0].cv.height,mk=()=>mkCanvas(fw,fh*vs.length);
  const al=mk(),hm=mk(),nm=mk();vs.forEach((v,i)=>{const m=mapsOf(v);al.getContext('2d').drawImage(v.cv,0,i*fh);hm.getContext('2d').drawImage(m.height,0,i*fh);nm.getContext('2d').drawImage(m.normal,0,i*fh);});
  return{albedo:al,height:hm,normal:nm,frameW:fw,frameH:fh};}
function spriteMeta(){const w=getWeapon(),fr=getVillainFrames();return{
  note:'1px outline padding included: sprite pixel (x,y) = grid (x-1,y-1). Normal maps are OpenGL style (green = +Y up). Height: 0..255 = 0..'+HMAX+' px toward the viewer.',
  body:{frameW:fr[0].img.width,frameH:fr[0].img.height,frames:fr.length,poses:{walk6:WALK6,idle:IDLE,blink:BLINK,walk8:WALK8},
    sheets:{'villain_*':'off hand holds the orb','villain_armed_*':'off hand holds the second weapon (arm is on weapon_off_*)'},
    anchor:{x:VG.cx+1,y:VG.cy+1},gunShoulder:{x:VG.sx+1,y:VG.sy+1},offShoulder:{x:VG.ox+1,y:VG.oy+1},
    perFrame:fr.map(f=>({bob:f.bob,lean:f.lean,anchors:Object.fromEntries(Object.entries(f.anchors).map(([n,q])=>[n,{x:q.x+1,y:q.y+1}]))}))},
  weaponAnchors:Object.fromEntries(WBENDS.map(b=>[b,Object.fromEntries(Object.entries(getWeaponBent(b).anchors).map(([n,q])=>[n,{x:q.x+WG.px+1,y:q.y+WG.py+1}]))])),
  weapon:{w:w.cv.width,h:w.cv.height,bendRows:WBENDS,levelRow:WBENDS.indexOf(WBEND0),bendRule:'bend=clamp(round(1+(up>0?3*up:2*up)),-2,4), up=-sin(aim)',pivot:{x:WG.px+1,y:WG.py+1},muzzleX:w.muz,gunY:w.gunY},
  build:{ammo:AMMO[build.ammo].id,frame:FRAMES[build.frame].id,items:build.items.slice()}};}
