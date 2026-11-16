{ pkgs, lib, systemConfig, expectedRevision }:
let
  app = systemConfig.services.remote-zettel;
  web = systemConfig.systemd.services.remote-zettel;
in
assert app.evenDeviceReadAccess.enable;
assert builtins.length app.evenDeviceReadAccess.ownerSubjects == 1;
assert web.environment.ENABLE_EVEN_DEVICE_READS == "true";
assert web.environment.EVEN_DEVICE_STATE_DIR == "/var/lib/remote-zettel/even-devices";
assert web.environment.READING_LIST_STATE_PATH == "/var/lib/remote-zettel/reading-list-progress.json";
assert lib.elem "remote-zettel" web.serviceConfig.StateDirectory;
assert builtins.fromJSON web.environment.EVEN_DEVICE_OWNER_SUBJECTS_JSON == app.evenDeviceReadAccess.ownerSubjects;
assert lib.elem "remote-zettel/even-devices" web.serviceConfig.StateDirectory;
assert web.serviceConfig.StateDirectoryMode == "0700";
assert app.package.evenDeviceFeatures;
assert app.package.evenWriting;
assert lib.hasInfix "zz-even-writing.conf" systemConfig.system.activationScripts.remote-zettel-writing-trial-cleanup.text;
assert lib.hasInfix "888532bcb266c19973e29042cc3f0bf8ac77dafe02856fe65c55bfaeae66919f" systemConfig.system.activationScripts.remote-zettel-writing-trial-cleanup.text;
assert lib.hasInfix "inbox notes archive writing" systemConfig.system.activationScripts.remote-zettel-acls.text;
assert lib.hasInfix "u:remote-zettel:rwX,u:$data_owner:rwX,g:remote-zettel-data:rwX,m::rwX" systemConfig.system.activationScripts.remote-zettel-acls.text;
assert lib.hasInfix (builtins.unsafeDiscardStringContext (toString app.package)) web.serviceConfig.ExecStart;
assert app.cloudflareAccess.publicHostname == "zettel.ss-damon.com";
pkgs.runCommandLocal "even-device-persistence-test" {} ''
  test -f ${app.package}/lib/remote-zettel/src/server/even-device-access.js
  grep -q evenDeviceFeaturePath ${app.package}/lib/remote-zettel/src/server/even-device-access.js
  grep -Fq '"commit":"${expectedRevision}"' ${app.package}/lib/remote-zettel/build-revision.json
  test -f ${app.package}/lib/remote-zettel/src/adapters/reading-list.js
  grep -q FileReadingList ${app.package}/lib/remote-zettel/src/server/app.js
  test -f ${app.package}/lib/remote-zettel/src/adapters/writing.js
  test -f ${app.package}/lib/remote-zettel/src/even/writing.js
  grep -q FileWriting ${app.package}/lib/remote-zettel/src/server/app.js
  grep -q evenDeviceWritingPath ${app.package}/lib/remote-zettel/src/server/even-device-access.js
  grep -Fq 'Writing: browse, create and edit files' ${app.package}/lib/remote-zettel/src/server/even-device-page.js
  touch "$out"
''
