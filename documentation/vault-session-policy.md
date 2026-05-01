# Vault Session Policy

Android Diogel uses two separate session timers:

- **In-app inactivity timeout** locks the vault when the user stops interacting with Diogel while it is open.
- **Background lock delay** locks the vault after Diogel has been sent to the background.

Shorter delays are safer because private signing capability leaves memory sooner. Longer delays are more convenient for normal signer workflows where users briefly switch apps.

`Never while app is running` only disables locking caused by backgrounding while the current Android process stays alive. It does not persist an unlocked vault across app restart, process death, device reboot, or manual lock. When the process starts again, the vault must still be unlocked explicitly.

The manual **Lock Vault** action is always available and immediately clears the unlocked session.
