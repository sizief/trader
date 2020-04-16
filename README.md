## What  
Different bots to market making on crypto currencies exchanges.  
  
## How
- Run `market_maker_huobi` to SIMULATE buying and selling on `Huobi.com`. IT will buy when market is upward and sell when it is downward.  
  
- Run `market_making_limit` to start market making on `exir.io`. It is not a simulation, you need to get the credentials and store it in `.env`
  
- Run `market_making_limit_fast` to start market making on `exir.io`. The difference between this and last one is that it is working with less chance of lossing money, but also less chance of making profit.

- Also `market_making_dual` is work in progress. I am not going to spend time on it soon. The idea is doing market making on pair of excahnges, without a need to withdraw or deposit for future trades.
