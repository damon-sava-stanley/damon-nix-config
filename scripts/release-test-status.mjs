// Read-only authenticated deployment projection; no approval or delivery methods.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const p = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const { readDeploymentStatus } = await import(pathToFileURL(p.application + '/src/work/deployment-status.js'));
process.stdout.write(JSON.stringify(await readDeploymentStatus(
  '/run/remote-zettel-deployment-status/read.sock', p.repository, 'deeley', 0)));
