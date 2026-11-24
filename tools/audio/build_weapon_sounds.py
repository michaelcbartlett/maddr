"""Synthesize layered gun, blade and impact sounds. Original, license-free, deterministic.

Writes 44.1 kHz mono WAVs to godot/audio/weapons. Needs numpy only.
"""
from pathlib import Path
import wave
import numpy as np

OUT=Path(__file__).resolve().parents[2]/'godot/audio/weapons'
SR=44100


def t_(dur):return np.arange(int(SR*dur))/SR


def band(x,low,high):
    """Smooth-edged FFT band-pass."""
    f=np.fft.rfftfreq(len(x),1/SR);s=np.fft.rfft(x)
    up=1/(1+(low/np.maximum(f,1))**6);down=1/(1+(f/high)**6)
    return np.fft.irfft(s*up*down,len(x))


def decay(t,fast,hold=0.):return np.exp(-np.maximum(0,t-hold)/fast)


def sweep(t,f0,f1,speed):
    f=f1+(f0-f1)*np.exp(-t/speed);return np.sin(2*np.pi*np.cumsum(f)/SR)


def norm(x,peak):
    x=x-np.mean(x);fade=min(len(x),int(.006*SR));x[-fade:]*=np.linspace(1,0,fade)
    return x/np.max(np.abs(x))*peak


def room(x,rng,amount,length):
    """Short street slap-back so shots have space around them."""
    n=int(SR*length);ir=rng.standard_normal(n)*np.exp(-np.arange(n)/(SR*length*.28));ir=band(ir,250,4200)
    ir/=np.sqrt(np.sum(ir**2))
    wet=np.convolve(x,ir)[:len(x)+n];out=np.zeros(len(x)+n);out[:len(x)]+=x
    late=int(.018*SR);out[late:]+=wet[:len(out)-late]*amount*.5;return out


def gun(rng,dur,crack,body,body_from,body_to,thump,mech,tail,drive):
    t=t_(dur);noise=rng.standard_normal(len(t))
    x=band(noise,1800,9500)*decay(t,crack)*1.5                                   # supersonic crack
    x+=band(rng.standard_normal(len(t)),220,2400)*decay(t,body)*1.25             # powder blast
    x+=sweep(t,body_from*rng.uniform(.94,1.06),body_to,.022)*decay(t,thump)*1.35 # chest thump
    x[:int(.0012*SR)]+=np.linspace(1.6,0,int(.0012*SR))                          # hard leading edge
    if mech:                                                                     # slide and case
        at=int(mech*rng.uniform(.92,1.1)*SR);m=t_(.03)
        click=band(rng.standard_normal(len(m)),2500,7500)*decay(m,.004)+.5*np.sin(2*np.pi*rng.uniform(2600,3300)*m)*decay(m,.006)
        end=min(len(x),at+len(m));x[at:end]+=click[:end-at]*.28
    x=np.tanh(x*drive)
    return room(x,rng,.5,tail)


def blade(rng,dur,low,high,buzz,ring):
    """A spinning blade leaving the launcher: spring snap, rising zip, whirr."""
    t=t_(dur);k=t/dur;noise=rng.standard_normal(len(t));x=np.zeros(len(t))
    # moving band: crossfade narrow noise bands upward for a true zip
    centers=np.geomspace(low,high,7)
    for i,c in enumerate(centers):
        place=i/(len(centers)-1);x+=band(noise,c*.8,c*1.25)*np.exp(-((k-place*.75)/.16)**2)*(.8+.5*place)
    x/=np.max(np.abs(x))
    spin=buzz*(1+.5*k);x*=.55+.45*np.sign(np.sin(2*np.pi*np.cumsum(spin)/SR))*np.exp(-k*1.2)+.2
    zip_tone=sweep(t,high*.22,high*.62,dur*.5);x+=.22*zip_tone*np.sin(np.pi*np.clip(k*1.4,0,1))
    for partial,level in [(1,.22),(2.76,.14),(5.4,.08)]:x+=level*np.sin(2*np.pi*ring*partial*t+rng.uniform(0,6))*decay(t,.05)
    s=t_(.012);x[:len(s)]+=band(rng.standard_normal(len(s)),900,6000)*decay(s,.003)*1.1
    env=np.minimum(1,t/.003)*np.clip((1-k)/.35,0,1);return np.tanh(x*env*1.5)


def ping(rng,base,dur):
    t=t_(dur);x=np.zeros(len(t))
    for partial,level,d in [(1,.9,.10),(2.76,.6,.06),(4.1,.35,.045),(5.4,.4,.035),(8.9,.2,.02)]:
        x+=level*np.sin(2*np.pi*base*partial*(1-.05*t/dur)*t+rng.uniform(0,6))*decay(t,d*rng.uniform(.85,1.15))
    x+=band(rng.standard_normal(len(t)),3000,11000)*decay(t,.004)*1.2
    return np.tanh(x*.9)


def whine(rng,f0,f1,dur):
    """Bullet ricochet off a hard surface."""
    t=t_(dur);k=t/dur;f=f0+(f1-f0)*k**.6+35*np.sin(2*np.pi*rng.uniform(16,24)*t)
    x=np.sin(2*np.pi*np.cumsum(f)/SR)*decay(t,dur*.35)*.7+band(rng.standard_normal(len(t)),f1,f0*2)*decay(t,.03)*.5
    x+=band(rng.standard_normal(len(t)),2500,9000)*decay(t,.003)*1.4;return np.tanh(x)


def thud(rng):
    t=t_(.09);return np.tanh(band(rng.standard_normal(len(t)),300,2600)*decay(t,.012)*1.6+sweep(t,210,90,.01)*decay(t,.02))


GUNS={'pistol':dict(dur=.16,crack=.010,body=.030,body_from=260,body_to=85,thump=.040,mech=.075,tail=.22,drive=1.5,peak=.62),
    'blunder':dict(dur=.30,crack=.016,body=.075,body_from=170,body_to=42,thump=.110,mech=0,tail=.42,drive=2.1,peak=.82),
    'rifle':dict(dur=.20,crack=.014,body=.040,body_from=310,body_to=70,thump=.055,mech=.095,tail=.36,drive=1.8,peak=.72),
    'repeater':dict(dur=.11,crack=.008,body=.020,body_from=290,body_to=105,thump=.026,mech=.048,tail=.14,drive=1.4,peak=.50)}


def save(name,x,peak):
    data=(norm(np.asarray(x,float).copy(),peak)*32767).astype('<i2')
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(SR);f.writeframes(data.tobytes())


def main():
    OUT.mkdir(parents=True,exist_ok=True);count=0
    def put(group,i,x,peak):
        nonlocal count
        save(f'{group}_{i+1}',x,peak);count+=1
    for g,(name,spec) in enumerate(GUNS.items()):
        spec=dict(spec);peak=spec.pop('peak')
        for i in range(5):put('gun_'+name,i,gun(np.random.default_rng(1000+g*50+i),**spec),peak)
    for i in range(6):
        rng=np.random.default_rng(2000+i);put('blade',i,blade(rng,rng.uniform(.17,.23),rng.uniform(700,950),rng.uniform(6200,8200),rng.uniform(85,125),rng.uniform(1900,2500)),.5)
    for i in range(5):rng=np.random.default_rng(3000+i);put('blade_ping',i,ping(rng,rng.uniform(1700,2700),.28),.36)
    for i in range(4):rng=np.random.default_rng(4000+i);put('ricochet',i,whine(rng,rng.uniform(3300,4300),rng.uniform(1200,1700),rng.uniform(.22,.32)),.3)
    for i in range(4):put('bullet_hit',i,thud(np.random.default_rng(5000+i)),.4)
    print(count,'sounds in',OUT)


if __name__=='__main__':main()
