# IPFS appData Hashes & Upload Instructions

Deterministic JSON payloads for CoWSwap appData (ETH/Base, staging/production) live in this folder:

- `eth-staging.json`
- `eth-production.json`
- `base-staging.json`
- `base-production.json`

Hashes (keccak-256 over the minified JSON bytes):

- ETH staging: `0xeb584a62763e79eeb1ead9afa1a107d0cd1afd5f8a872939b3d9fdce92733dc9`
- ETH production: `0xc723e76767ed11bb2ebf1314f3edd33703a1ed3d9305f33a33678f9b5876cce8`
- Base staging: `0x42fa1d1e8db1ce9ffd141f1b4673e94ef1c0ee5c4b3b3af94420276849165628`
- Base production: `0x36a0cdee81024d6ad00ae83cf3a1b776b2220eb7f818f7abb28aa9dd06eb6e1d`

Local IPFS upload (keccak-256, CIDv1):

```bash
# Ensure the deterministic JSON is present (already in this folder)
for f in eth-staging eth-production base-staging base-production; do
  ipfs add --cid-version=1 --hash=keccak-256 --pin assets/appdata/$f.json
done
```

Resulting CIDs (CIDv1, base32):

- ETH staging: `bafkrwihllbfge5r6phxld2wzv6q2cb6qzunp2x4kq4uttm6z7xhje4z5ze`
- ETH production: `bafkrwigheptwoz7ncg5s5pytctz63uzxaoq62pmtaxztum3hr6nvq5wm5a`
- Base staging: `bafkrwicc7ior5dnrz2p72fa7dndhh2ko6hao4xclhm5psrbae5uesfswfa`
- Base production: `bafkrwibwudg65aicjvvnacxihtz2dn3wwira5n7ydd32xmukvhoqn23odu`

Notes:

- Pinning services may default to SHA2-256/CIDv0; for keccak/CIDv1, add locally (or with a service that supports arbitrary multihash) and use `pinByHash` if available.
- To keep pins online, run `ipfs daemon` with the same `IPFS_PATH` that holds the pins.
