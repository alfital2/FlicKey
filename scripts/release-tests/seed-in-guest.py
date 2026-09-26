import json
import os
import plistlib
import subprocess
import sys
import time

assert os.getuid() == 501 and os.path.exists('/Users/admin/.flickey-test-vm')
scenario = sys.argv[1]
now = int(time.time())
domain = 'com.talalfi.FlicKey'
state = {'firstRun': now, 'maxElapsed': 0, 'lastNag': now}
if scenario in ('ExpiredTrialBlocksConversionAndOffersPurchase', 'ReleaseIgnoresTrialResetAndLicensedSimulationArguments'):
    state['firstRun'] -= 31 * 86400
elif scenario == 'ClockRollbackCannotReviveExpiredTrial':
    state['maxElapsed'] = 30 * 86400
elif scenario == 'RunningAppLocksWhenTrialExpires':
    state['firstRun'] -= 30 * 86400 - 30
data = json.dumps(state).encode()
preferences = {
    'trialStateBackup.v1': data, 'welcomeTourSeen': True,
    'whatsNewSeenVersion': '0.5.0', 'SUEnableAutomaticChecks': False,
    'rememberVisitedApps': False,
}
if scenario == 'FreshInstallGetsFiniteTrial':
    preferences = {}
    data = b'{}'
subprocess.run(['/Users/admin/ReleaseGate/trial-fixture', data.decode()], check=True)
subprocess.run(['/usr/bin/defaults', 'delete', domain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['/usr/bin/defaults', 'import', domain, '-'], input=plistlib.dumps(preferences), check=True)
print('Prepared production trial fixture:', scenario, flush=True)
