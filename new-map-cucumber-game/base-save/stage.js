// stage.js: copy the patched mirrors that install.lua / install2.lua push whole into this folder (serve.ps1 serves one flat dir).
const fs = require('fs'), path = require('path');
const here = __dirname, up = path.join(here, '..');
for (const [from, to] of [
  ['DataService.lua', 'DataService.lua'],
  ['PetHatchService.server.lua', 'PetHatchService.server.lua'],
  [path.join('build-mode', 'BuildService.server.lua'), 'BuildService.server.lua'],
  ['EggPlacement.server.lua', 'EggPlacement.server.lua'],
  ['BenchRuntimeMesh.lua', 'BenchRuntimeMesh.lua'],
]) {
  fs.copyFileSync(path.join(up, from), path.join(here, to));
  console.log('staged ' + to + ' (' + fs.statSync(path.join(here, to)).size + ' bytes)');
}
