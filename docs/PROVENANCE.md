# Source provenance

Transferred on 2026-11-07 from the working Kobo Codex prototype. The Python-generated SOURCE-MANIFEST.json records SHA-256 hashes for byte-preserved source/reference/history files. The shareable ZIP's explicit file allowlist seeded the transfer; newer installed test/status documents were included separately.

`reference/app-server-schema/` contains generated schemas used to verify app-server interfaces. `reference/koreader-v2026.07.1/` contains selected unmodified upstream sources extracted from the official Kobo release used for the device update, with the upstream COPYING file. These are reference material, not replacement KOReader core modules. Official archive SHA-256: `0f36a62ce73b12516f969e4ad7862cc06920afb03c7bd4db29a0d990bdd84b2f`.

Historical installer scripts depend on the original `outputs/kobo-codex` and `work` layout, private backup markers, and a USB-mounted Kobo. They are preserved as work history under `legacy-work/installers/`; adapt and review them before reuse. Do not run them blindly from this new project.

The transfer excludes the original `.private` tree, connection.json, installation.json, certificates/keys/auth, rollback archives, captured images, PDFs, Swift/build caches, compiled OCR/transport binaries, Node modules and the official KOReader archive itself. No third-party annotation plugin has been installed as part of this handoff.

## Upstream references

- Codex app-server: https://developers.openai.com/codex/app-server
- KOReader release: https://github.com/koreader/koreader/releases/tag/v2026.07.1
- Native PDF stylus annotation request: https://github.com/koreader/koreader/issues/8537
- Selected pen input API source: https://github.com/koreader/koreader/blob/v2026.07.1/frontend/device/input.lua

Upstream feature status is time-sensitive; recheck before planning an upgrade. The current prototype's pen API enables our pad; it does not add native PDF drawing.
