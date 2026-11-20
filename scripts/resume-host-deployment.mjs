// Immutable operator-only commissioning/readiness helper. No delivery capability.
import { existsSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const [application, configuration, operation, staging] = process.argv.slice(2);
if (process.getuid?.() !== 0 || !application?.startsWith('/nix/store/')) throw Error('Root immutable application required');
const load = name => import(pathToFileURL(application + '/src/work/' + name + '.js'));
const { loadDeploymentRuntime } = await load('deployment-runtime');
const { DeploymentPublicationDelivery } = await load('deployment-delivery');
const { readDeploymentSocket } = await load('deployment-status');
const c = loadDeploymentRuntime(configuration);
if (operation === 'initialize' || operation === 'verify') {
  const file = operation === 'initialize' ? staging : c.deliveryStatePath;
  if (!file || (operation === 'initialize' && existsSync(file))) throw Error('Fresh staged journal required');
  const delivery = new DeploymentPublicationDelivery(file, c.policy,
    { read() { throw Error('Publication reads are unavailable during commissioning'); }, close() {} },
    { send() { throw Error('Deployment is unavailable during commissioning'); } },
    operation === 'initialize' ? 'create-only' : 'existing-only');
  try { if (delivery.pendingSelection()) throw Error('Unexpected pending delivery'); }
  finally { await delivery.close(); }
} else if (operation === 'ready') {
  const selection = await readDeploymentSocket(c.publisherSocket,
    { action: 'read-deployment-selection', sourceId: c.policy.publication.publication.sourceId }, 4096);
  if (selection.version !== 1 || selection.sourceId !== c.policy.publication.publication.sourceId) throw Error('Publisher enrollment mismatch');
  const status = await readDeploymentSocket(c.statusSocketPath, { action: 'read-deployment-status' });
  if (status.target !== c.policy.target || status.repository !== c.repository
      || status.policyDigest !== c.policy.controllerPolicyDigest
      || ![null, 'no-running-evidence'].includes(status.error)) throw Error('Deployment status is not ready');
} else throw Error('Unsupported commissioning operation');
process.stdout.write(JSON.stringify({ policyDigest: c.policy.controllerPolicyDigest }));
