<h1>STAE Stablecoin Platform</h1>	

This repository contains the core smart contracts for the STAE Stablecoin Platform. The system uses cryptoassets as collateral to peg the stablecoin to a FIAT. THe system supports BTC, ETH, and any ERC20 tokens as collateral to help peg the stablecoin. Each collateral will have its own risk parameters to incentivize Backers (market makers) to maintain the peg.

This document assumes the reader has read the whitepaper and has a basic understanding of the ecosystem.

<h2>Collateral</h2>
  
  The collateral is the foundation of all stablecoins created by STAE. Each stablecoin is backed/collateralized by a cryptoasset with a FIAT value such as ETH, BTC, any ERC20 token, or any ERC827 token. Other cryptoassets on other blockchains may be added in the future and will be handled similar to BTC. This additional collateral type must be approved by the STAE foundation and owners of the governance token Backer through a voting process. Careful consideration is required when adding new collateratal types to determine the appropriate risk parameters based on liquidity, volatility, and other factors associated with the asset to support the peg of the stable coin.
  
  The collateral tellers handle the deposit and withdrawal of the collateral into CDPs (collateralized debt positions). For non-ETH blockchains such as BTC, we require watchers that monitor the BTC blockchain and updates the CDP store when a deposit is detected in a registered BTC receiving address.
  
<h2>Savings Token</h2>

