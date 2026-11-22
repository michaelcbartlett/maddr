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
    <p class="hint">Open the basic cop as separate body parts, linked joints, and an editable baton.</p>
    <div class="row"><label for="godotProjectPath">Project</label><input id="godotProjectPath" readonly style="width:100%" aria-label="Godot project"></div>
    <div class="row"><label for="godotScriptPath">Script</label><input id="godotScriptPath" readonly value="enemies/enemy_painter.gd" style="width:100%"></div>
    <div class="btns"><button id="godotChooseScript">Choose .gd…</button><button id="godotReconnect">Connect again</button></div>
    <input id="godotScriptFile" type="file" accept=".gd" hidden>
    <div class="row"><label for="godotCharacter">Character</label><select id="godotCharacter"><option value="cop">Basic cop</option></select></div>
    <div class="row"><label for="godotAnimation">Animation</label><select id="godotAnimation"><option value="walk">Walk · 8 frames</option><option value="idle">Idle · 4 frames</option><option value="attack">Baton attack · 3 frames</option></select></div>
    <p id="godotBridgeStatus" class="hint" role="status" aria-live="polite"></p>
    <p class="hint">Supports this project's enemy_painter.gd through the cop adapter. Other GDScript files need a matching adapter. Save project keeps your puppet edits; game integration is separate.</p>
    <div class="dialogActions"><button id="godotCancel">Cancel</button><button id="godotImport" class="primary" disabled>Open editable puppet</button></div>`;
  document.body.append(dialog);
  const el = id => document.getElementById(id);
  let catalog = null, selectedSource = null, running = false;
  let connectVersion = 0;
  const message = text => { el('godotBridgeStatus').textContent = text; };

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
      el('godotScriptPath').value = result.script;
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
    for (const id of ['godotImport', 'godotCancel', 'godotChooseScript', 'godotReconnect', 'godotAnimation']) el(id).disabled = value;
    if (!value) el('godotImport').disabled = !catalog;
  }

  async function importCharacter() {
    if (!catalog || running) return;
    setRunning(true);
    message('Preparing the cop’s body parts and joints in Godot…');
    try {
      const result = await request('/api/godot/open', {
        method: 'POST', headers: {'Content-Type': 'application/json', 'X-PixelStudio-Token': catalog.token},
        body: JSON.stringify({character: 'cop', animation: el('godotAnimation').value, script: catalog.script, source: selectedSource})
      });
      const before = frames;
      await openStudio(new File([JSON.stringify(result.project)], 'cop-' + el('godotAnimation').value + '.pixelstudio', {type: 'application/json'}));
      if (frames === before) { message('Import was cancelled or the project could not be loaded. Your artwork is still open.'); return; }
      syncWeaponAnchors();
      renderImportedControls();
      el('layerTimelineDetails').open = false;
      fit();
      dialog.close();
      status(`Basic cop · ${el('godotAnimation').value} · ${frames.length} frames · ${layerDefs.length} linked parts · select a part and press T to rotate`);
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
  el('godotChooseScript').onclick = () => el('godotScriptFile').click();
  el('godotScriptFile').onchange = async event => {
    const file = event.target.files[0];
    event.target.value = '';
    if (!file) return;
    selectedSource = null;
    if (file.name !== 'enemy_painter.gd' || file.size > 250000) {
      el('godotImport').disabled = true;
      message('Choose enemies/enemy_painter.gd from the project above. This version supports its basic cop; other scripts need a matching adapter.');
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
      const p = frame.poses?.['layer-baton'];
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
  for (const [label, id] of [['Edit baton', 'layer-baton'], ['Edit arm', 'layer-near-upper-arm'], ['Edit torso', 'layer-torso']]) {
    const b = document.createElement('button');
    b.textContent = label;
    b.onclick = () => { stopPlay(); selectLayer(id); setWorkspace('paint'); el('surface').value = 'art'; updateSurfaceUI(); setPaintTool('rotateLayer'); el('layerControls').scrollIntoView({block: 'start'}); draw(); };
    controls.append(b);
  }
  button.insertAdjacentElement('afterend', controls);
  function renderImportedControls() {
    controls.hidden = !layerDefs.some(layer => layer.id === 'layer-baton');
    controls.style.display = controls.hidden ? 'none' : '';
  }
  const previousRenderLayers = renderLayers;
  renderLayers = function(...args) { const result = previousRenderLayers.apply(this, args); renderImportedControls(); return result; };
  if (new URLSearchParams(location.search).get('godot') === 'cop') setTimeout(() => openDialog(true), 0);
})();
