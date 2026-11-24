"""Cartoon special deaths (poison, radiation melt, burnt) for each enemy. Never queues."""
import shutil
import build_h3_cop as cop
import build_h3_detective as det
from build_h3_sprite_pack import PACK
import queue_h3_animations as queue

OUT=PACK.parent/'special-deaths'
ROOM='He is drawn small with wide empty space around him and stays that size and in the same area of the frame. '
NO='Clean family-cartoon slapstick: no blood, bones, gore or open wounds. No smoke, gas clouds, bubbles floating away, sparks, glow, stars or other particles; the game adds effects. Nothing else is in the picture.'


def shots(who,hat,held):
    return [
     ('poisoned','A single cartoon collapse from feeling sick.',ROOM+f'Neutral until 0.3. {who} turns pale then pea-green, cheeks puff out, eyes bulge and water, both hands grab the throat and belly, {held} drops to the ground. Two queasy wobbles from side to side until 1.8, knees turn to jelly, then a stiff topple backward toward screen-left onto the back by 2.6, tongue sticking out, {hat} tilted over one eye. One small twitch of a foot at 3.2. From 3.6 completely still, skin still green, fully inside the frame.'),
     ('melted','A single cartoon melt into a puddle, like a wax candle.',ROOM+f'Neutral until 0.3. {who} looks at his own hands in surprise as his colors turn sickly yellow-green. From 0.6 he softens like warm wax: shoulders droop, arms stretch long and drip, face sags comically, then the whole body slumps smoothly straight down, keeping its clothing colors as swirls, spreading into a flat rounded puddle on the ground line by 2.8. The {hat} floats down and settles on top of the puddle, with {held} lying beside it. From 3.2 to 5.0 only the still puddle, {hat} and {held} remain, fully inside the frame. No skeleton.'),
     ('burnt','A single cartoon turning to ash, with no flames.',ROOM+f'Neutral until 0.3. Starting from the edges, {who} darkens evenly to solid sooty black like burnt toast by 1.2, keeping his exact shape; only two round white blinking eyes show. He holds the pose, blinks twice, coughs once, then at 2.4 his shape crumbles straight down from the top into a neat small pile of dark gray ash by 3.2. The charred {hat} rests on the pile. From 3.4 completely still, fully inside the frame. No fire at any time.'),
    ]


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    shutil.copy2(cop.OUT/'references/cop-small.png',refs/'cop-small.png');shutil.copy2(det.OUT/'references/det-small.png',refs/'det-small.png')
    shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    rows=[];number=151
    for key,module,who,hat,held in [('cop',cop,'The officer','peaked cap','the baton'),('det',det,'The detective','fedora','the revolver')]:
        for name,summary,action in shots(who,hat,held):
            text=module.prompt(summary,action,NO)
            # These deaths change the silhouette on purpose; relax the identity clamp after the start.
            text=text.replace('in every frame. One baton only.','until the change described above begins. One baton only.').replace('in every frame. The fedora stays on unless stated.','until the change described above begins.')
            ident=f'{number}-{key}-{name}';number+=1
            rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':key+'-small.png','item_reference':'proxy-grip.png','motion_reference':None,'prompt':text})
            (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    print([j['id'] for j in queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))])


if __name__=='__main__':main()
