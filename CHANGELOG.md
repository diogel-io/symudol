# Changelog

## 1.0.0 (2026-10-17)


### Features

* **accounts:** add profile picture support and enhance IdentityTile UI ([e89a933](https://github.com/diogel-io/symudol/commit/e89a933cd6787602a08decae14fbe5d8a26868d0))
* **icons:** add adaptive monochrome icon and update app launcher icons ([6716522](https://github.com/diogel-io/symudol/commit/67165227a7ab1df80aa0218d6f94a54117ab72dd))
* **nip46:** implement NIP-46 session services, crypto handlers, and approval policies ([5f7c109](https://github.com/diogel-io/symudol/commit/5f7c109ca6977f362152ef7103baa929bf84344c))
* **nip55:** auto-approve decrypt operations and fix permission grants ([bd65d8f](https://github.com/diogel-io/symudol/commit/bd65d8f70c9202ef1e3d1f593ff40e82bb253aff))
* **nip55:** enhance relay-specific permissions and make authorities dynamic ([e4d1b1d](https://github.com/diogel-io/symudol/commit/e4d1b1d6ac47f632aff5ca92f44324d0077e8330))
* **nip55:** make decrypt_zap_event rememberable with cross-scope grant matching ([2e09ee0](https://github.com/diogel-io/symudol/commit/2e09ee06aee28acc3eadf04abd7a998bdf87e8f3))
* **profile:** add support for Nostr profile metadata and dynamic avatar loading ([d7dcdbd](https://github.com/diogel-io/symudol/commit/d7dcdbd2dbf8bc98523d08bfa1fff88b143bf4df))
* **requests:** add curated Nostr event-kind registry with labels and risk notes ([882470c](https://github.com/diogel-io/symudol/commit/882470cb125aadcc1bba4ebb46a8100b400f47f3))
* **requests:** add known app descriptions and manual NIP-55 verification tool ([5b21a12](https://github.com/diogel-io/symudol/commit/5b21a124bd7a12dd081ec443b20d95dae7f8c548))
* show the app as Symudol ([1e31933](https://github.com/diogel-io/symudol/commit/1e319337f1345a3148e0b29279b1367c0a5c83c2)), closes [#38](https://github.com/diogel-io/symudol/issues/38)
* **signing:** add support for decrypting NIP-04 anon tags ([4219edf](https://github.com/diogel-io/symudol/commit/4219edf1e06c0357a6b88c27699a0bf5eab26f16))
* **tests:** add Amethyst-style NIP-55 sign_event fixture data ([ec6b478](https://github.com/diogel-io/symudol/commit/ec6b478ba255d1ab438c8c65caed2a29310e9054))
* **tests:** add comprehensive unit tests for NIP-55 signEvent and request codecs ([1982bd8](https://github.com/diogel-io/symudol/commit/1982bd83cb00dca29383ec20567c4502616cab82))
* **tests:** add NIP-37 and NIP-09 request summary tests and kind-specific logic ([9e13261](https://github.com/diogel-io/symudol/commit/9e13261d756213993aa12d8fe2dd4645e9786c98))
* **vault:** implement PIN-derived key encryption with Argon2id + AES-GCM ([3b211e0](https://github.com/diogel-io/symudol/commit/3b211e04c1b9aa8521c4c3452b3e8eb89a404bc2))


### Bug Fixes

* **nip55:** a lock always wins over the unlock before it ([ed34c44](https://github.com/diogel-io/symudol/commit/ed34c44c4ce400c2c7fa74c3294247990ceca4e6))
* **nip55:** a lock always wins over the unlock before it ([3eecf8b](https://github.com/diogel-io/symudol/commit/3eecf8bfaf38c92e575e29d68d3234da6f9b4262)), closes [#13](https://github.com/diogel-io/symudol/issues/13)
* **nip55:** check current_user and require an integer kind natively ([ed2dcc4](https://github.com/diogel-io/symudol/commit/ed2dcc4b4873f4c7e3468b8f537ab581bc732185))
* **nip55:** check current_user and require an integer kind natively ([2c5f160](https://github.com/diogel-io/symudol/commit/2c5f1604e3981d3922c02fedf47f0b4b97e125f1)), closes [#10](https://github.com/diogel-io/symudol/issues/10)
* **nip55:** clear the native key when the vault locks or the app goes ([7ef127f](https://github.com/diogel-io/symudol/commit/7ef127ff143f015d2f3f6208a4cdca30e8fca7cf))
* **nip55:** clear the native key when the vault locks or the app goes ([4435bab](https://github.com/diogel-io/symudol/commit/4435bab78ed5159d3c9c95df49f5aae785adc46d)), closes [#9](https://github.com/diogel-io/symudol/issues/9)
* **nip55:** never attribute a request to Symudol itself ([1b92336](https://github.com/diogel-io/symudol/commit/1b92336bead078023e123e3bd7a1ba3791221ab2))
* **nip55:** never attribute a request to Symudol itself ([729ab2c](https://github.com/diogel-io/symudol/commit/729ab2cf4cb48f8f321bb0dbeb33bd38382d4174)), closes [#11](https://github.com/diogel-io/symudol/issues/11)
* **nip55:** never remember or auto-approve signing any event kind ([649ba12](https://github.com/diogel-io/symudol/commit/649ba12f9d3129723b16f2c8936a6e664039b23f))
* **nip55:** never remember or auto-approve signing any event kind ([f8c17a2](https://github.com/diogel-io/symudol/commit/f8c17a29df4073090de397862474c271b5a02fca)), closes [#5](https://github.com/diogel-io/symudol/issues/5)
* **nip55:** never sign an event serialisation as a sign_message ([80fd290](https://github.com/diogel-io/symudol/commit/80fd290b3d8c4e465261eb62e7bb742d173908a3))
* **nip55:** never sign an event serialisation as a sign_message ([527d2a6](https://github.com/diogel-io/symudol/commit/527d2a60f3c6e117f748fe4ecc2be3d2b1c9ac40)), closes [#8](https://github.com/diogel-io/symudol/issues/8)
* **nip55:** never sign natively; Dart signs and verifies ([bd52475](https://github.com/diogel-io/symudol/commit/bd524759b330083d583ab6eba0e4420e9e377c2e))
* **nip55:** never sign natively; Dart signs and verifies ([de9aa5d](https://github.com/diogel-io/symudol/commit/de9aa5d15925bbe90bcbc83ec0ba97d3fc7877ab)), closes [#12](https://github.com/diogel-io/symudol/issues/12)
* **nip55:** take NIP-55 requests only from the bridge, never from intent extras ([5ca0362](https://github.com/diogel-io/symudol/commit/5ca03622282cd381e366af1cc6e054289a34be87))
* **nip55:** take NIP-55 requests only from the bridge, never from intent extras ([d0edf29](https://github.com/diogel-io/symudol/commit/d0edf2977334974666b5ffeb08505ecf3b1fa8d8)), closes [#7](https://github.com/diogel-io/symudol/issues/7)
* **profile:** fetch profile metadata only when the user asks ([bf71777](https://github.com/diogel-io/symudol/commit/bf7177758581d45f23e2ebd4eb05999b92726559))
* **profile:** fetch profile metadata only when the user asks ([2b1710c](https://github.com/diogel-io/symudol/commit/2b1710cdce73a2dd6205ca9fc67c160899210d13)), closes [#83](https://github.com/diogel-io/symudol/issues/83)
* **requests:** show the key get_public_key will share ([af65718](https://github.com/diogel-io/symudol/commit/af65718f32bd821c6944a8953c87344ca1396dc9))
* **requests:** show the key get_public_key will share ([560a84b](https://github.com/diogel-io/symudol/commit/560a84b0ba1fa4493fe262a073bca8ba5817512a))
* **requests:** stop refetching the active profile on each visit ([#83](https://github.com/diogel-io/symudol/issues/83)) ([a040caa](https://github.com/diogel-io/symudol/commit/a040caa5f71c2894a9e4aa235001ddf87ccc35fa))


### Continuous Integration

* cut releases from a release-please release PR ([a6fd182](https://github.com/diogel-io/symudol/commit/a6fd182bf749feddea177f1b42d6aa1a7f016c76))
