# Radicale interoperability fixture

This disposable fixture uses Radicale with a local plaintext htpasswd file, explicit rights and
filesystem collection metadata. `init.sh` creates typed CalDAV/CardDAV collections and seed
objects before leaving the server running. The local credentials are `interop` /
`interop-password`.

The validated image was pinned by digest:
`docker.io/kozea/radicale:latest@sha256:a86aad569e810c7240f4ef60478d237ba2598f642416798c7c63025e64ba9007`.
The digest identifies OCI image version `nightly-20260821` (revision
`b968b2baab5a16be8b86c4b94b86595d12236173`). The tag is retained only as a
human-readable alias; the digest is the reproducibility anchor.
