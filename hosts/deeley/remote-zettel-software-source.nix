# Explicit create-only source commissioning. No service switch or credentials.
{ pkgs, remote-zettel-software, remote-zettel-software-source, ... }:
let
  app = remote-zettel-software.packages.${pkgs.stdenv.hostPlatform.system}.default;
  snapshot = remote-zettel-software-source.outPath;
  source = "/var/lib/remote-zettel-software-source/sources/software-v1/source";
  state = "/var/lib/remote-zettel-software-source-state";
  policy = "/var/lib/remote-zettel-software-source-policy";
  initialize = pkgs.writeText "remote-zettel-software-source-commission.mjs" ''
    import { createHash } from 'node:crypto';
    import { constants, fsyncSync, openSync, closeSync, writeFileSync, lstatSync, fstatSync, readFileSync } from 'node:fs';
    import { commissionProtectedPublicationSource, ProtectedPublicationSource } from '${app}/lib/remote-zettel/src/work/publication-source-advance.js';
    import { canonicalPromotionJson } from '${app}/lib/remote-zettel/src/work/publisher-candidate-input.js';
    if (process.getuid() !== 0) throw Error('Root required');
    const configuration = { repository: '${source}', stateDirectory: '${state}' };
    const verify = process.argv[2] === '--verify';
    if (verify) {
      for (const parent of ['${policy}', '/var/lib', '/var', '/']) {
        const info = lstatSync(parent);
        if (!info.isDirectory() || info.uid !== 0 || (info.mode & 0o022)) throw Error('Unsafe source policy parent');
      }
      const fd = openSync('${policy}/source-pin.json', constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
      let pin;
      try {
        const info = fstatSync(fd);
        if (!info.isFile() || info.uid !== 0 || info.gid !== 0 || info.nlink !== 1 || (info.mode & 0o777) !== 0o600 || info.size > 65536) throw Error('Unsafe source pin');
        pin = JSON.parse(readFileSync(fd, 'utf8'));
      } finally { closeSync(fd); }
      if (Object.keys(pin).sort().join(',') !== 'configuration,policyDigest' || canonicalPromotionJson(pin.configuration) !== canonicalPromotionJson(configuration)) throw Error('Source pin configuration mismatch');
      const owner = new ProtectedPublicationSource(configuration);
      try {
        const actual = createHash('sha256').update(canonicalPromotionJson(owner.policy())).digest('hex');
        if (actual !== pin.policyDigest) throw Error('Source policy mismatch');
      } finally { owner.close(); }
      console.log('Existing protected source verified.');
      process.exit(0);
    }
    commissionProtectedPublicationSource(configuration, '15edcc27575cbd703aa6c49853d759dcc81da4e4');
    const owner = new ProtectedPublicationSource(configuration);
    try {
      const policyDigest = createHash('sha256').update(canonicalPromotionJson(owner.policy())).digest('hex');
      const fd = openSync('${policy}/source-pin.json', constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      try { writeFileSync(fd, canonicalPromotionJson({ configuration, policyDigest })); fsyncSync(fd); }
      finally { closeSync(fd); }
      const directory = openSync('${policy}', constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
      try { fsyncSync(directory); } finally { closeSync(directory); }
    } finally { owner.close(); }
    console.log('Source commissioned; execution, publication and deployment remain inactive.');
  '';
  tool = pkgs.writeShellApplication {
    name = "remote-zettel-software-commission-source";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils ];
    text = ''
      test "$#" = 1 || { echo 'Expected --commission or --verify'; exit 2; }
      test "$EUID" = 0 || { echo 'Root required'; exit 1; }
      if test "$1" = --verify; then
        exec ${pkgs.nodejs_24}/bin/node ${initialize} --verify
      fi
      test "$1" = --commission || { echo 'Expected --commission or --verify'; exit 2; }
      for path in /var/lib/remote-zettel-software-source ${state} ${policy}; do
        test ! -e "$path" && test ! -L "$path" || { echo "Existing or partial state: $path"; exit 1; }
      done
      install -d -m 0700 /var/lib/remote-zettel-software-source/sources/software-v1 ${policy}
      install -d -m 0755 ${state}
      cp -R --no-preserve=ownership ${snapshot} ${source}
      chmod -R u+rwX ${source}
      chmod 0700 ${source}
      test -z "$(find -P ${source} -xdev \( ! -user root -o -perm /022 -o -type l \) -print -quit)"
      ${pkgs.nodejs_24}/bin/node ${initialize}
    '';
  };
in {
  environment.systemPackages = [ tool ];
  system.build.remoteZettelSoftwareSourceCommission = tool;
}
