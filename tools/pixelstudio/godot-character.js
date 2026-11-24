// Loaded after PixelStudio. The Godot adapter runs locally; artwork remains editable offline.
(() => {
  'use strict';
  if (document.getElementById('openGodotCharacter')) return;
  const endpoint = /^https?:$/.test(location.protocol) && ['127.0.0.1', 'localhost'].includes(location.hostname)
    ? location.origin : 'http://127.0.0.1:8766';
  const button = document.createElement('button');
  button.id = 'openGodotCharacter';
  button.textContent = 'Open Godot character';
  document.getElementById('sheetImport').insertAdjacentElement('beforebegin', button);
  const dialog = document.createElement('dialog');
  dialog.id = 'godotCharacterDialog';
  dialog.innerHTML = `<h2>Open Godot character</h2>
    <p class="hint">Open any game character and animation. Humanoids open as linked puppets (arms, legs, head, held prop); dogs, drones, vehicles and death tumbles open as one paintable layer.</p>
    <div class="row"><label for="godotProjectPath">Project</label><input id="godotProjectPath" readonly style="width:100%" aria-label="Godot project"></div>
    <div class="row"><label for="godotScriptPath">Script</label><input id="godotScriptPath" readonly value="enemies/enemy_painter.gd" style="width:100%"></div>
    <div class="btns"><button id="godotChooseScript">Choose .gd…</button><button id="godotReconnect">Connect again</button></div>
    <input id="godotScriptFile" type="file" accept=".gd" hidden>
    <div class="row"><label for="godotCharacter">Character</label><select id="godotCharacter"><option value="cop">Basic cop</option></select></div>
    <div class="row"><label for="godotAnimation">Animation</label><select id="godotAnimation"><option value="walk">Walk · 8 frames</option><option value="idle">Idle · 4 frames</option><option value="attack">Baton attack · 3 frames</option></select></div>
    <p id="godotBridgeStatus" class="hint" role="status" aria-live="polite"></p>
    <p class="hint">The doctor supports primary and dual sword/knife setups. Save project keeps your editable parts and poses.</p>
    <div class="dialogActions"><button id="godotCancel">Cancel</button><button id="godotImport" class="primary" disabled>Open editable puppet</button></div>`;
  document.body.append(dialog);
  const el = id => document.getElementById(id);
  let catalog = null, selectedSource = null, running = false;
  let connectVersion = 0;
  const message = text => { el('godotBridgeStatus').textContent = text; };
  const query = new URLSearchParams(location.search);
  const animationNames = {walk:'Walk · 8 frames',idle:'Idle · 4 frames',attack:'Baton attack · 3 frames',
    'primary-sword':'Primary sword','primary-knife':'Primary knife','dual-sword':'Dual swords','dual-knife':'Dual knives'};
  const STATE_ORDER = ['walk','idle','attack','panic','hurt','stunned','frozen','death'];
  const stateRank = id => { const i = STATE_ORDER.indexOf(id); return i < 0 ? 3.5 : i; };
  function animationLabel(character, id) {
    if (!character.frames && animationNames[id]) return animationNames[id];
    const name = id.charAt(0).toUpperCase() + id.slice(1);
    const n = character.frames?.[id];
    return n ? `${name} · ${n} frame${n === 1 ? '' : 's'}` : name;
  }
  function renderCharacter() {
    const character = catalog?.characters.find(c => c.id === el('godotCharacter').value);
    if (!character) return;
    const previous = el('godotAnimation').value;
    const ids = character.frames ? [...character.animations].sort((a, b) => stateRank(a) - stateRank(b) || a.localeCompare(b)) : character.animations;
    el('godotAnimation').replaceChildren(...ids.map(id => new Option(animationLabel(character, id),id)));
    const desired = character.animations.includes(previous) ? previous : query.get('animation');
    if (character.animations.includes(desired)) el('godotAnimation').value = desired;
    el('godotScriptPath').value = character.script || catalog.script;
    selectedSource = null;
  }

  async function request(path, options = {}, timeout = 90000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      const response = await fetch(endpoint + path, {...options, signal: controller.signal});
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Could not open this character.');
      return result;
    } finally { clearTimeout(timer); }
  }

  async function connect() {
    const version = ++connectVersion;
    el('godotImport').disabled = true;
    catalog = null;
    message('Connecting to local Godot…');
    try {
      const result = await request('/api/godot/catalog', {}, 3000);
      if (version !== connectVersion) return false;
      if (result.bridge !== 'pixelstudio-godot-v1') throw new Error('A different service is using the bridge port.');
      catalog = result;
      el('godotProjectPath').value = result.project;
      const desired = query.get('godot') || el('godotCharacter').value;
      const groups = {}; const groupName = c => c.id === 'doctor' ? 'Villain' : c.family === 'hero' ? 'Heroes' : c.id.startsWith('civ_') ? 'Civilians' : c.family === 'human' ? 'Police & guards' : 'Animals, drones & vehicles';
      for (const c of result.characters) (groups[groupName(c)] ||= []).push(c);
      el('godotCharacter').replaceChildren(...Object.entries(groups).map(([label, list]) => {
        const g = document.createElement('optgroup'); g.label = label; g.append(...list.map(c => new Option(c.name, c.id))); return g; }));
      if (result.characters.some(c => c.id === desired)) el('godotCharacter').value = desired;
      if (version === 1) el('godotAnimation').replaceChildren(); // first connect: honour ?animation=
      renderCharacter();
      el('godotImport').disabled = false;
      message('Connected. Choose an animation, then open the editable puppet.');
      return true;
    } catch (error) {
      if (version === connectVersion) message('Start Open PixelStudio.bat in E:\\repos\\mad villain, then click Connect again. ' + (error.name === 'AbortError' ? '' : error.message));
      return false;
    }
  }

  function setRunning(value) {
    running = value;
    for (const id of ['godotImport', 'godotCancel', 'godotChooseScript', 'godotReconnect', 'godotAnimation','godotCharacter']) el(id).disabled = value;
    if (!value) el('godotImport').disabled = !catalog;
  }

  async function importCharacter() {
    if (!catalog || running) return;
    setRunning(true);
    message('Preparing the editable character in Godot…');
    try {
      const result = await request('/api/godot/open', {
        method: 'POST', headers: {'Content-Type': 'application/json', 'X-PixelStudio-Token': catalog.token},
        body: JSON.stringify({character:el('godotCharacter').value,animation:el('godotAnimation').value,script:el('godotScriptPath').value,source:selectedSource})
      });
      const before = frames;
      await openStudio(new File([JSON.stringify(result.project)],el('godotCharacter').value+'-'+el('godotAnimation').value+'.pixelstudio',{type:'application/json'}));
      if (frames === before) { message('Import was cancelled or the project could not be loaded. Your artwork is still open.'); return; }
      syncWeaponAnchors();
      renderImportedControls();
      el('layerTimelineDetails').open = false;
      fit();
      dialog.close();
      status(`${el('godotCharacter').selectedOptions[0].textContent} · ${el('godotAnimation').value} · ${layerDefs.length} linked parts · select a part and press T to rotate`);
    } catch (error) {
      message(error.name === 'AbortError' ? 'Godot took too long. Connect again and retry.' : error.message);
    } finally { setRunning(false); }
  }

  async function openDialog(autoImport = false) {
    if (!dialog.open) dialog.showModal();
    if (await connect()) if (autoImport && !frames.length) await importCharacter();
  }
  button.onclick = () => openDialog();
  el('godotReconnect').onclick = connect;
  el('godotCancel').onclick = () => dialog.close();
  dialog.addEventListener('cancel', event => { if (running) event.preventDefault(); });
  el('godotImport').onclick = importCharacter;
  el('godotCharacter').onchange = renderCharacter;
  el('godotChooseScript').onclick = () => el('godotScriptFile').click();
  el('godotScriptFile').onchange = async event => {
    const file = event.target.files[0];
    event.target.value = '';
    if (!file) return;
    selectedSource = null;
    const expected = el('godotScriptPath').value.split('/').pop();
    if (file.name !== expected || file.size > 250000) {
      el('godotImport').disabled = true;
      message('Choose '+el('godotScriptPath').value+' from the project above.');
      return;
    }
    selectedSource = await file.text();
    el('godotImport').disabled = !catalog;
    message('Selected ' + file.name + '. Choose an animation and open its editable puppet.');
  };

  // Source art is already posed in each cel. The stored grip angle supplies the direction
  // at angle=0; layer transforms add their rotation and propagate through the existing rig.
  function syncWeaponAnchors() {
    for (const frame of frames) {
      const p = frame.poses?.['layer-primary-weapon'] || frame.poses?.['layer-baton'];
      if (!p || !Number.isFinite(p.attachmentAngle)) continue;
      const hand = posePoint(p, p.px, p.py);
      frame.socket = {x: hand.x, y: hand.y, angle: p.attachmentAngle + (p.angle || 0)};
    }
  }
  const previousArtChanged = artChanged;
  artChanged = function(...args) { syncWeaponAnchors(); return previousArtChanged.apply(this, args); };

  const controls = document.createElement('div');
  controls.id = 'godotPuppetControls';
  controls.className = 'grp';
  controls.hidden = true;
  controls.style.display = 'none';
  for (const [label, id] of [['Edit baton','layer-baton'],['Edit arm','layer-near-upper-arm'],['Edit torso','layer-torso'],
    ['Primary blade','layer-primary-weapon'],['Primary arm','layer-primary-upper-arm'],['Primary hand','layer-primary-hand'],
    ['Secondary blade','layer-secondary-weapon'],['Secondary arm','layer-secondary-upper-arm'],['Secondary hand','layer-secondary-hand'],['Doctor body','layer-doctor-body']]) {
    const b = document.createElement('button');
    b.textContent = label;
    b.dataset.layer = id;
    b.onclick = () => { stopPlay(); selectLayer(id); setWorkspace('paint'); el('surface').value = 'art'; updateSurfaceUI(); setPaintTool('rotateLayer'); el('layerControls').scrollIntoView({block: 'start'}); draw(); };
    controls.append(b);
  }
  button.insertAdjacentElement('afterend', controls);
  function renderImportedControls() {
    for (const b of controls.children) b.hidden = !layerDefs.some(layer => layer.id === b.dataset.layer);
    controls.hidden = ![...controls.children].some(b => !b.hidden);
    controls.style.display = controls.hidden ? 'none' : '';
  }
  const previousRenderLayers = renderLayers;
  renderLayers = function(...args) { const result = previousRenderLayers.apply(this, args); renderImportedControls(); return result; };
  if (query.get('godot')) setTimeout(() => openDialog(true), 0);
})();
