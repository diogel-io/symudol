sealed class VaultState {
  const VaultState();
}

final class NoVault extends VaultState {
  const NoVault();
}

final class VaultLocked extends VaultState {
  const VaultLocked();
}

final class VaultUnlocked extends VaultState {
  const VaultUnlocked();
}

final class SessionExpired extends VaultState {
  const SessionExpired();
}
