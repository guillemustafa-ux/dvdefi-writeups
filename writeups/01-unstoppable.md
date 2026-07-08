# 01 — Unstoppable

**Class:** Broken accounting invariant / griefing (denial of service)
**Goal:** Stop the vault from offering flash loans (turn a working feature into a permanent revert).

## The setup

`UnstoppableVault` is an ERC-4626 tokenized vault that also acts as an ERC-3156
flash lender. A separate `UnstoppableMonitor` periodically calls
`checkFlashLoan(...)`; if a flash loan ever *fails*, the monitor pauses the vault
and hands ownership back to the deployer. Our job is to make that health check
fail.

## Root cause

`flashLoan` enforces this line before lending:

```solidity
uint256 balanceBefore = totalAssets();               // = asset.balanceOf(vault)
if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();
```

`convertToShares(totalSupply)` equals `totalSupply * totalSupply / totalAssets`.
This only equals the raw token balance while shares and assets are pegged 1:1 —
i.e. while every token in the vault arrived through `deposit()` (which mints
shares). The check conflates two things that ERC-4626 deliberately keeps
separate:

- **`totalSupply`** — internal share accounting, only moved by mint/burn.
- **`asset.balanceOf(this)`** — the raw ERC-20 balance, which *anyone* can inflate
  with a direct `transfer` that mints no shares.

A plain ERC-20 transfer into the vault desynchronizes the two permanently, so the
strict equality can never hold again and every future `flashLoan` reverts.

## Exploit

One transaction, no contract needed:

```solidity
token.transfer(address(vault), 1); // donate 1 wei of the asset, no shares minted
```

From now on `balanceBefore = totalAssets = 1_000_000e18 + 1` while
`convertToShares(totalSupply)` still reflects `1_000_000e18` worth of shares. The
`InvalidBalance` revert fires, the monitor's `try/catch` catches it, and the
monitor pauses the vault and transfers ownership to the deployer — satisfying the
solved condition.

## Remediation

Never derive an internal invariant from an externally mutable balance. Options:

- Track deposited assets in an internal accumulator updated only on
  deposit/withdraw, and compare against that (not `balanceOf`).
- If you must read `balanceOf`, tolerate *donations* (`balance >= expected`)
  instead of requiring strict equality — direct transfers can only increase the
  balance, so `>=` is safe where `==` is a footgun.
- Drop the redundant check entirely; ERC-4626 conversions already handle the
  share/asset relationship.

## Real-world parallel

The "direct-transfer breaks `balanceOf`-based accounting" bug is the same root
cause behind ERC-4626 **inflation/donation attacks** and many vault share-price
manipulations. Any protocol that treats `token.balanceOf(this)` as authoritative
internal state is exposed to unsolicited transfers.
