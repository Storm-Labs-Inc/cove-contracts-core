# IPFS appData Hashes & Upload Instructions

Deterministic JSON payloads for CoWSwap appData (ETH/Base, staging/production) live in this folder:

- `eth-staging.json`
- `eth-production.json`
- `base-staging.json`
- `base-production.json`

Hashes (keccak-256 over the minified JSON bytes):

- ETH staging: `0x561b978a4985d1e9fd61363eca21c8d05b03dbc0524bdd1bade3bec2debd256b`
- ETH production: `0xa9407a3cd5deda012a6466f5b7b68c3ced758743cbb058aa104f81b153a44531`
- Base staging: `0x85f967c312f5b4963ab3266e6307f4b37b4c5d9e37459a1515a913208e949a2d`
- Base production: `0x2d6e5a9324d4bda7e4e2eb3b46e4dd260fd352f66c0457673c1fcbcd81915976`

Local IPFS upload (keccak-256, CIDv1):

```bash
# Ensure the deterministic JSON is present (already in this folder)
for f in eth-staging eth-production base-staging base-production; do
  ipfs add --cid-version=1 --hash=keccak-256 --pin assets/appdata/$f.json
done
```

Resulting CIDs (CIDv1, base32):

- ETH staging: `bafkrwicwdolyusmf2hu72yjwh3fcdsgqlmb5xqcsjporxlpdx3bn5pjfnm`
- ETH production: `bafkrwifjib5dzvo63iasuzdg6w33ndb45v2yoq6lwbmkuecpqgyvhjcfge`
- Base staging: `bafkrwief7ft4gexvwsldvmzgnzrqp5ftpngf3hrxiwnbkfnjcmqi5fe2fu`
- Base production: `bafkrwibnnznjgjguxwt6jyxlhndojxjgb7jvf5tmarlwopa7zpgydekzoy`

## Verification

To verify the appData hash and CID manually, use the CoW Protocol AppData Explorer:
https://explorer.cow.fi/appdata?tab=encode

1. Paste the JSON content from the relevant file
2. Verify the computed `appDataHash` matches the hash listed above
3. Verify the IPFS CID matches the CID listed above

## Notes

- Pinning services may default to SHA2-256/CIDv0; for keccak/CIDv1, add locally (or with a service that supports arbitrary multihash) and use `pinByHash` if available.
- To keep pins online, run `ipfs daemon` with the same `IPFS_PATH` that holds the pins.
