# Historical implementation work

Installers in this directory preserve the development/installation history. They are coupled to the original workspace's paths and private backup state, and are not portable release installers. The working source is at the project root; current status and proposed architecture are under docs/.

Large upstream archives, compiled dependencies/caches, private profiles and device backups were intentionally left in their original local workspace. See the gitignored .local/OPERATIONS.md for operational pointers. No implementation milestone should be inferred as complete merely because a historical script exists.
