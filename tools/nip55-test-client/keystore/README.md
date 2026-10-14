# Test-client keystore

`test-client.jks` signs the NIP-55 test client. It is **test-only** and committed on purpose.

- Symudol matches remembered grants on package and signing certificate, so the client needs a
  certificate that is the same on every machine and in CI.
- It signs nothing but `io.diogel.nip55testclient` and grants nothing outside that app. It is not,
  and must never become, Symudol's signing key.
- Store and key password: `nip55-test-client`. Alias: `test-client`.
- Certificate SHA-256:
  `DF:9A:D3:AF:8A:19:FA:F6:CF:A3:F5:3C:1A:ED:71:8E:3F:52:07:83:5D:07:F4:0F:F7:90:50:14:70:F6:A6:D0`
