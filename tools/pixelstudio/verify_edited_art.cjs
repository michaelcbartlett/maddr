// Compare the asset renderer to PixelStudio's actual affine rasterizer, without a browser shim.
const fs = require('node:fs'), vm = require('node:vm'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const editor = fs.readFileSync('E:/repos/video to frames/index.html', 'utf8');
function editorFunction(name) {
  const start = editor.indexOf('function ' + name + '(');
  assert(start >= 0, name);
  // Functions used here have no template or string braces; balance their body explicitly.
  let body = editor.indexOf('{', editor.indexOf(')', start)), depth = 1, end = body + 1;
  // Default object arguments aren't present on the extracted geometry functions.
  while (depth && end < editor.length) { if (editor[end] === '{') depth++; if (editor[end] === '}') depth--; end++; }
  return editor.slice(start, end);
}
const [sourcePath, validationPath, matchedPath] = process.argv.slice(2);
const sourceBytes = fs.readFileSync(sourcePath), project = JSON.parse(sourceBytes), expected = JSON.parse(fs.readFileSync(validationPath));
assert.equal(crypto.createHash('sha256').update(sourceBytes).digest('hex'), expected.source_sha256);
class ImageData { constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); } }
const context = vm.createContext({ImageData, Math, Number, Uint8ClampedArray, W: project.width, H: project.height, activeLayer: null});
vm.runInContext(`
const layerPixels=(fr,id)=>fr.cels[id]||null;
const layerPose=(fr,id)=>fr.poses[id]||{x:0,y:0,sx:1,sy:1};
${['rawLayerBounds','layerBounds','poseMatrix','posePoint','layerCorners','rasterizedLayer'].map(editorFunction).join('\n')}
`, context);
for (const [i, frame] of project.frames.entries()) {
  context.frame = {poses: frame.poses, cels: Object.fromEntries(Object.entries(frame.cels).map(([id, data]) => [id, {data: new Uint8ClampedArray(Buffer.from(data, 'base64'))}]))};
  const composite = Buffer.alloc(project.width * project.height * 4);
  for (const layer of project.layers) {
    if (!layer.visible || layer.opacity === 0) continue;
    context.id = layer.id;
    const part = vm.runInContext('rasterizedLayer(frame,id).data', context);
    for (let pixel = 0; pixel < part.length; pixel += 4) if (part[pixel + 3]) composite.set(part.subarray(pixel, pixel + 4), pixel);
  }
  assert.equal(crypto.createHash('sha256').update(composite).digest('hex'), expected.frames[i].art_sha256, 'Frame ' + (i + 1) + ' must match the editor rasterizer');
}
const matched = JSON.parse(fs.readFileSync(matchedPath));
assert.deepEqual(matched.layers, project.layers);
for (let i = 0; i < project.frames.length; i++) {
  assert.deepEqual(matched.frames[i].cels, project.frames[i].cels);
  assert.deepEqual(matched.frames[i].poses, project.frames[i].poses);
  assert.equal(crypto.createHash('sha256').update(Buffer.from(matched.frames[i].maps.normal, 'base64')).digest('hex'), expected.frames[i].normal_sha256);
}
console.log('PASS: ' + project.frames.length + ' edited frames match PixelStudio rasterization; all layers/poses preserved, matched normals embedded.');
