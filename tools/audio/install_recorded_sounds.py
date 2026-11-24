"""Cut CC0 recordings into game-ready weapon sounds.

Usage: python -I install_recorded_sounds.py <folder with x-firearm, x-swish, x-sword-attack, x-sword-clash>
Sources and licenses: godot/audio/weapons/CREDITS.txt
"""
from pathlib import Path
import struct
import sys
import wave
import av
import numpy as np

OUT=Path(__file__).resolve().parents[2]/'godot/audio/weapons'
SR=44100


def read_wav(p):
    b=p.read_bytes();pos=12;fmt=None;data=b''
    while pos+8<=len(b):
        k,n=b[pos:pos+4],struct.unpack('<I',b[pos+4:pos+8])[0]
        if k==b'fmt ':fmt=struct.unpack('<HHIIHH',b[pos+8:pos+24])
        if k==b'data':data=b[pos+8:pos+8+n];break
        pos+=8+n+(n&1)
    tag,ch,sr,_,_,bits=fmt
    if bits==16:x=np.frombuffer(data[:len(data)//2*2],'<i2')/32768
    else:
        r=np.frombuffer(data[:len(data)//3*3],np.uint8).reshape(-1,3).astype(np.int32);x=((r[:,0]|r[:,1]<<8|r[:,2]<<16)<<8>>8)/8388608
    return x[:len(x)//ch*ch].reshape(-1,ch).mean(1),sr


def read_any(p):
    if p.suffix=='.wav':return read_wav(p)
    with av.open(str(p)) as c:
        sr=c.streams.audio[0].rate;r=av.AudioResampler(format='fltp',layout='mono',rate=sr);parts=[]
        for frame in c.decode(audio=0):parts+=[f.to_ndarray()[0] for f in r.resample(frame)]
    return np.concatenate(parts).astype(float),sr


def resample(x,sr):
    if sr==SR:return x
    n=int(round(len(x)*SR/sr));s=np.fft.rfft(x);m=n//2+1
    out=np.zeros(m,complex);k=min(m,len(s));out[:k]=s[:k]
    return np.fft.irfft(out,n)*n/len(x)


def attack(x,near):
    """Exact start of the shot near an approximate time: first sample above 12% of the local peak."""
    a=max(0,int((near-.12)*SR));b=min(len(x),int((near+.25)*SR));part=np.abs(x[a:b])
    return a+int(np.argmax(part>.12*part.max()))


def finish(x,seconds,peak,drive=1.):
    x=x[:int(seconds*SR)].copy();x-=x.mean();x/=np.abs(x).max()
    if drive>1:x=np.tanh(x*drive)/np.tanh(drive)
    f=max(1,int(len(x)*.45));x[-f:]*=np.cos(np.linspace(0,np.pi/2,f))**2
    h=int(.0008*SR);x[:h]*=np.linspace(0,1,h)
    return x/np.abs(x).max()*peak


def save(name,x):
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(SR);f.writeframes((x*32767).astype('<i2').tobytes())


GUNS={'gun_pistol':(.5,.7,6.,[('1911/A_42P',[.94,5.0]),('Walther PPQ/X_39P',[1.41,6.45,10.66]),('Smith & Wesson 642/V_27P',[.81])]),
    'gun_rifle':(.85,.8,6.5,[('Mosin Nagant/M_21P',[1.03,5.02,9.15,14.13]),('1917/B_24P',[1.31]),('Savage 10 .300 Blackout/T_27P',[.95])]),
    'gun_blunder':(.9,.85,7.,[('Mossberg/N_30P',[1.70,4.96]),('Nova/O_21P',[.43,3.46]),('CD/H_21P',[.47,3.08])]),
    'gun_repeater':(.30,.6,5.,[('PPSh/P_30P',[.97,4.38,8.24,11.42,15.09]),('Carl Gustav M45/G_31P',[.31,3.5])])}


def main():
    root=Path(sys.argv[1]);OUT.mkdir(parents=True,exist_ok=True);report={}
    for group,(seconds,peak,drive,takes) in GUNS.items():
        for old in OUT.glob(group+'_*.wav*'):old.unlink()
        n=0
        for name,times in takes:
            file=next((p for p in (root/'x-firearm').rglob(name.split('/')[1]+'.wav')),None)
            if not file:print('missing',name);continue
            x,sr=read_wav(file);x=resample(x,sr)
            for t in times:
                n+=1;save(f'{group}_{n}',finish(x[attack(x,t)-int(.002*SR):],seconds,peak,drive))
        report[group]=n
    def simple(group,folder,seconds,peak,pick=None):
        files=sorted((root/folder).rglob('*.*'),key=lambda p:int(''.join(c for c in p.stem if c.isdigit()) or 0))
        files=[p for p in files if p.suffix in ('.wav','.ogg')]
        if pick:files=[p for p in files if int(''.join(c for c in p.stem if c.isdigit()) or 0) in pick]
        for old in OUT.glob(group+'_*.wav*'):old.unlink()
        for n,p in enumerate(files,1):
            x,sr=read_any(p);x=resample(x,sr);level=np.abs(x);start=max(int(np.argmax(level>.03*level.max())),int(np.argmax(level>.5*level.max()))-int(.07*SR))
            save(f'{group}_{n}',finish(x[max(0,start-60):],seconds,peak))
        report[group]=len(files)
    simple('blade','x-swish',.25,.6,{1,3,4,5,6,7,8,9})      # launched razor blades
    simple('knife','x-swish',.2,.55,{2,10,11,12,13})        # quick stabs
    simple('sword','x-sword-attack',.6,.65)
    simple('blade_ping','x-sword-clash',.45,.5)
    (OUT/'CREDITS.txt').write_text('''Weapon sounds, all CC0 (public domain), cut and leveled by tools/audio/install_recorded_sounds.py

gun_*: The Free Firearm Sound Library - Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney
  https://opengameart.org/content/the-free-firearm-sound-library
blade_*, knife_*: Swishes Sound Pack - artisticdude
  https://opengameart.org/content/swishes-sound-pack
sword_*, blade_ping_*: 20 Sword Sound Effects (Attacks and Clashes) - StarNinjas
  https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes
bullet_hit_*, ricochet_*: synthesized by tools/audio/build_weapon_sounds.py
''',encoding='utf-8')
    print(report)


if __name__=='__main__':main()
