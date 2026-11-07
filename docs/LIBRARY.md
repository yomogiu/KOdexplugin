# Private PDF library and Kobo sync layout

## Local folders

```text
library/                    Entire tree is gitignored
  pdfs/                     PDFs to read and sync; subfolders are welcome
  kobo-state/               Reserved for reader state/metadata copied from Kobo
  indexes/                  Reserved for local extraction and search indexes
```

Put your PDFs in `library/pdfs/`. Keep the same relative subfolder names when
copying them to the Kobo. The entire library tree is ignored, so `.sdr` folders,
extracted text, metadata, and index files cannot accidentally become tracked
merely because they are not PDFs. Local folders are created with owner-only
permissions. Gitignore is a version-control rule, not encryption or an access
restriction on the Codex process.

Empty ignored directories do not survive a fresh Git checkout. To recreate them:

```sh
mkdir -p library/pdfs library/kobo-state library/indexes
chmod 700 library library/pdfs library/kobo-state library/indexes
```

## Kobo counterpart

| Location | PDF directory |
| --- | --- |
| Mac project | `library/pdfs/` |
| Kobo connected by USB on this Mac | `/Volumes/KOBOeReader/Books/KOdex/` |
| Same directory as seen inside KOReader | `/mnt/onboard/Books/KOdex/` |

`Books/KOdex/` is this project's chosen folder, not a required Kobo system path.
Kobo's official USB instructions allow copying PDFs into the mounted eReader
drive. KOReader's bundled Kobo device configuration defaults its file-browser
home to `/mnt/onboard`; users can choose a different home folder. If you already
maintain a preferred Books/Documents folder, use a KOdex subfolder there instead
of moving your existing collection.

The Kobo was not mounted when this layout was prepared, so its current custom
home-folder setting was not inspected and no device folders were changed.

## Current use

Connect the Kobo by USB and tap Connect. Create `Books/KOdex/` in the mounted
drive if it does not already exist, then copy PDFs from `library/pdfs/` into it,
preserving relative subfolders. Eject the drive before opening the files in
KOReader. You can browse to `/mnt/onboard/Books/KOdex` and optionally set it as
your KOReader home folder.

This change prepares the storage convention only. It does not synchronize
files, delete or replace existing books, start a watcher, index documents, or
send any document content to Codex. No cloud-sync service is configured.

## Future sync contract

Use `library/pdfs/` as the document tree on the Mac and the chosen KOdex folder
as its device counterpart. Start with explicit USB copies and no deletion
propagation. Handle changed files on both sides as conflicts rather than
silently overwriting one. Keep a content hash for document identity rather than
depending only on a filename.

KOReader can keep book state in sidecar `.sdr` directories or in its configured
metadata location. Future sync must inspect that setting, preserve the state,
and place imported metadata in `library/kobo-state/`; it must not blindly merge
live settings. `library/indexes/` is for future Mac-local extraction/indexing,
not files to copy onto the Kobo. Current bridge configuration and credentials
remain separate in their existing private runtime.

## Sources

- [Kobo's official USB PDF/ePub instructions](https://help.kobo.com/hc/en-us/articles/360024775093-Add-non-protected-PDF-and-ePub-files-to-your-Kobo-eReader-using-your-computer)
- [KOReader v2026.07.1 Kobo device configuration](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/device/kobo/device.lua)
- [KOReader file-browser home-folder handling](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/filemanager/filemanager.lua)
