# The web input includes the device features, browser/voice repairs and reading
# list and Writing. Retain the capabilities used by host checks.
# The independently pinned Work runtime remains unchanged.
{ package }:
package.overrideAttrs (old: {
  passthru = (old.passthru or {}) // { evenDeviceFeatures = true; evenWriting = true; };
})
