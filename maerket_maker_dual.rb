# This is not complete. Idea is to market making between two markets.
#
require_relative 'exir'
require 'dotenv/load'
require 'yaml'
require_relative './telegram'

class MarketMakerDual
  BTC = 'btc'
  TMN = 'tmn'

  def initialize
  end

  def call
    if order on one side and price gap ok
      do nothing
    else
      start_trade
    end
  end

  def start_trade
    if @exir.balance.currency == @nobitex.balance.currency
      log('both currenies are the same', true)
      return
    end

    create_btc_trade if @exir.balance.currency == BTC
    create_tmn_trade if @exir.balance.currency == TMN
  end

  def create_btc_trade
    return if @exir.order_books.asks.first < @nobitex.order_books.asks.first && @exir.order_books.bids.first < @nobitex.order_books.bids.first

    if @exir.order_books.asks.first > @nobitex.order_books.asks.first
      gap = @exir.order_books.asks.first - @nobitex.order_books.asks.first
      create_ask_order(@exir, gap, @nobitex) 
    elsif @exir.order_books.bids.first > @nobitex.order_books.asks.first
      create_bid_order(@nobitex, gap, @exir) 
    end
  end

  def create_ask_order(maker_exchange, gap, taker_exchange)
    maker_cost = maker_exchange.maker_fee * maker_exchange.asks.first
    taker_cost = taker_exchange.taker_fee* taker_exchange.asks.first

    if gap < maker_cost + taker_cost + 100_000
      log('gap is not enough', true)
      return
    end

    create_order(maker_exchange, ASK)
  end

  def create_order(exchange, side)
    
  end
  
  def create_ask(immediate_sell)
    order_params = ask_params(immediate_sell)
    create(params: order_params, immediate_sell: immediate_sell)
  end

  def bids_price_gap
    order_books.bids.first.price - order_books.bids[1].price
  end

  def bid_price
    price_index = (bids_price_gap < ACCEPTABLE_BID_GAP) ? 0 : 1
    order_books.bids[price_index].price
  end

  def bid_params
  :x
  bid_size = ((balance.tmn) / bid_price).floor(4)

    params = OrderParams.new(
      symbol: symbol,
      size: bid_size,
      side: 'buy',
      price: bid_price,
      type: ORDER_TYPE
    )

    logger.info("PREPARING_BID_ORDER: #{order_books}, #{balance.tmn}, #{params}")

    params
  end

  def ask_price(immediate_sell)
    return order_books.bids.first.price if immediate_sell

    ask_price = order_books.asks.first.price
    ask_price = buy_price if buy_price && ask_price < buy_price
    ask_price
  end

  def ask_params(immediate_sell)
    ask_size = balance.btc.floor(4)
    params = OrderParams.new(
      symbol: symbol,
      size: ask_size,
      side: 'sell',
      price: ask_price(immediate_sell),
      type: ORDER_TYPE
    )
    logger.info("PREPARING_ASK_ORDER: #{params}")

    params
  end


end
