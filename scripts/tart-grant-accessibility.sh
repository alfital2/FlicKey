#!/usr/bin/env bash
# Refresh Accessibility grants after an ad-hoc UI-test build changes CDHashes.
set -euo pipefail

derived="${FLICKEY_TEST_DERIVED_DATA:-/Users/admin/flickey-oss/build/DerivedData}"
app="$derived/Build/Products/Debug/FlicKey.app"
runner="$derived/Build/Products/Debug/FlicKeyUITests-Runner.app"
test -d "$app"
test -d "$runner"

make_requirement() {
    local bundle="$1" output="$2" requirement
    requirement="$(codesign -dr - "$bundle" 2>&1 | sed -E -n 's/^#? ?designated => //p')"
    test -n "$requirement"
    /usr/bin/csreq -r="$requirement" -b "$output"
}
make_requirement "$app" /tmp/flickey.csreq
make_requirement "$runner" /tmp/flickey-runner.csreq
/usr/bin/csreq -r='identifier "com.apple.Safari" and anchor apple' -b /tmp/safari.csreq
teams='/Applications/Microsoft Teams.app'
if [[ -d "$teams" ]]; then
    make_requirement "$teams" /tmp/teams.csreq
fi

sudo killall tccd 2>/dev/null || true
sleep 1
sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' <<SQL
INSERT OR REPLACE INTO access
 (service,client,client_type,auth_value,auth_reason,auth_version,csreq,
  indirect_object_identifier_type,indirect_object_identifier,flags,last_modified)
VALUES
 ('kTCCServiceAccessibility','com.talalfi.FlicKey',0,2,4,1,readfile('/tmp/flickey.csreq'),0,'UNUSED',0,strftime('%s','now')),
 ('kTCCServiceListenEvent','com.talalfi.FlicKey',0,2,4,1,readfile('/tmp/flickey.csreq'),0,'UNUSED',0,strftime('%s','now')),
 ('kTCCServiceAccessibility','com.talalfi.FlicKeyUITests.xctrunner',0,2,4,1,readfile('/tmp/flickey-runner.csreq'),0,'UNUSED',0,strftime('%s','now')),
 ('kTCCServicePostEvent','com.talalfi.FlicKeyUITests.xctrunner',0,2,4,1,readfile('/tmp/flickey-runner.csreq'),0,'UNUSED',0,strftime('%s','now'));
SQL

# Chat-memory tests never use calls, camera, or audio. Predeny those unrelated
# capabilities in the disposable guest so Teams cannot cover its chat UI with a
# first-launch privacy sheet. No permission is granted to Teams here.
if [[ -f /tmp/teams.csreq ]]; then
    sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" <<SQL
INSERT OR REPLACE INTO access
 (service,client,client_type,auth_value,auth_reason,auth_version,csreq,
  indirect_object_identifier_type,indirect_object_identifier,flags,last_modified)
VALUES
 ('kTCCServiceMicrophone','com.microsoft.teams2',0,0,4,1,readfile('/tmp/teams.csreq'),0,'UNUSED',0,strftime('%s','now')),
 ('kTCCServiceCamera','com.microsoft.teams2',0,0,4,1,readfile('/tmp/teams.csreq'),0,'UNUSED',0,strftime('%s','now'));
SQL
fi

killall CoreServicesUIAgent 2>/dev/null || true

# Safari URL reading uses Apple Events. This is a separate, target-specific
# consent row in the per-user database: FlicKey may control Safari, nothing else.
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" <<SQL
INSERT OR REPLACE INTO access
 (service,client,client_type,auth_value,auth_reason,auth_version,csreq,
  indirect_object_identifier_type,indirect_object_identifier,
  indirect_object_code_identity,flags,last_modified)
VALUES
 ('kTCCServiceAppleEvents','com.talalfi.FlicKey',0,2,4,1,readfile('/tmp/flickey.csreq'),
  0,'com.apple.Safari',readfile('/tmp/safari.csreq'),0,strftime('%s','now'));
SQL

checks=(
  'kTCCServiceAccessibility|com.talalfi.FlicKey'
  'kTCCServiceListenEvent|com.talalfi.FlicKey'
  'kTCCServiceAccessibility|com.talalfi.FlicKeyUITests.xctrunner'
  'kTCCServicePostEvent|com.talalfi.FlicKeyUITests.xctrunner'
)
for check in "${checks[@]}"; do
    service="${check%%|*}"; client="${check#*|}"
    granted="$(sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' \
      "SELECT auth_value FROM access WHERE service='$service' AND client='$client';")"
    [[ "$granted" == 2 ]] || { echo "$service grant failed for $client" >&2; exit 3; }
done
