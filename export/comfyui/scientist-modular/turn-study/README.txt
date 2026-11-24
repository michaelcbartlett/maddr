SCIENTIST TURN STUDY

Start ComfyUI and run "Queue Scientist Turn Study.bat" in the repository root.
It queues ONE new 5-second, 24fps, 768x768, 16-step H3 REF2VA study using the
existing clean workflow, scientist image, green grip proxy and installed LoRAs.

0.00-0.75s: hold the original right-facing three-quarter stance.
0.75-2.00s: turn the character toward the viewer; camera stays fixed.
2.00-3.00s: hold front-facing, with both shoulders and hands readable.
3.00-4.25s: continue into the matching left-facing three-quarter stance.
4.25-5.00s: hold left-facing.

The study is slow so a few clear frames can be chosen for the approximately
3-frame / 125ms in-game turn. It is not a five-second gameplay turn animation.
Both arms stay low and slightly clear of the torso for extraction. The same
anatomical hand retains the proxy throughout. The proxy turns with the subject
in this reference; the game will continue aiming its separate weapon layers
from the right stick. Review frontal anatomy and changing arm depth before
importing. H3 can still deviate from the requested motion.

This is prompt-driven. No old shoulder, elbow or walking guide is attached.
The launcher automatically uploads the two correct image references before
submitting. No generation was submitted while preparing these files.

Output:
ComfyUI-Shared/output/video/mad-villain-sprite/batch/39-right-front-left-turn/
Log:
repository .local/h3-turn-study-queue/queue-log.json

"Preview Scientist Turn Study.bat" lists the plan without uploads or queueing.
Rerunning skips an identical accepted job. Use --force for a deliberate new take,
or --seed NUMBER to request a different seed. Other existing queue jobs are kept.

Full prompt: 39-right-front-left-turn-prompt.txt
Editable workflow: 39-right-front-left-turn-workflow.json
API graph: 39-right-front-left-turn-api.json

Rebuild the pack with:
python tools/pixelstudio/build_h3_turn_study.py
