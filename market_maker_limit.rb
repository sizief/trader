# frozen_string_literal: true
#
# Good for steady market. SLOW seller.
# 
# 1. Place an order for buy. The price is as same as the best bid order.
# 2. After successful order compilation, place an order for sell with the price of a highest ask order
# 3. Check if price is higher than buy price, sell with buy price
# 4. If stop loss is passed, sell immeidatelly
# 5. Monitor the price to make sure we are the best order on both sides
# 4. Repeat
#
# USAGE: ruby market_maker_limit.rb
# BEWARE it will use all the money in the account
#
require_relative 'exir'
require 'dotenv/load'
require 'yaml'
require_relative './telegram'

class MarketMakerLimit
  Result = Struct.new(:ok, :message, :data)
  Price = Struct.new(:tmn, :btc)
  OrderParams = Struct.new(:symbol, :size, :side, :price, :type, keyword_init: true)
  OrderBook = Struct.new(:bids, :asks, keyword_init: true)
  OrderBookDetail = Struct.new(:price, :size, keyword_init: true)
  MARKET_SIDES = %w[buy sell].freeze
  ORDER_TYPE = 'limit'
  MINIMUM_ASK_PRICE = 100_000_000
  MAXIMUM_BID_PRICE = 140_000_000
  STOP_LOSS_LIMIT = 1_050_000
  WAIT_AFTER_LOSS = 60*30
  STOP_LOSS_DURATION = 60
  ACCEPTABLE_BID_GAP = 250_000

  attr_reader :exchange, :symbol, :logger

  def initialize(symbol:, logger: Logger.new('./log/mm-limit.log'), notification_enabled: false)
    @exchange = Exir.new(access_token: ENV['EXIR_ACCESS_TOKEN'], test: false)
    @symbol = symbol
    @logger = logger
    @telegram = Telegram.new
    @notification_enabled = notification_enabled
  end

  def notification(message)
    return unless @notification_enabled

    @telegram.send_message(message)
  end

  def call
    cancel if orders.count > 1 # keep one order at a time always

    if active_order?
      update_price
    else
      sleep 1
      refresh_orders
      return if balance.tmn < 20_000 && balance.btc < 0.0001 # check active_record? false positive
      return if active_order? # double check

      logger.info("CREATING ORDER: available orders: #{orders}")
      balance.tmn > balance.btc*buy_price ? create_bid : create_ask(false)
    end
  rescue StandardError => error
    notification(error)
  end

  private

  def save_order(order)
    return if sell?(order.side) # We are saving buy order here for now

    order = { price: order.price, size: order.size, time: Time.now.to_i }
    File.open('mm-limit_order.yml', 'w') { |file| file.write(order.to_yaml) }
  end

  def sell?(side)
    side == 'sell'
  end

  def buy?(side)
    side == 'buy'
  end

  def update_price
    order_price = orders.first['price'].to_f
    order_side = orders.first['side']
    order_size = orders.first['size']

    if sell?(order_side) && stop_loss_crossed_for?(STOP_LOSS_DURATION)
      sell_immediatelly
      return
    end

    # do nothing if we are selling at buy price and we are not the best ask price
    if (order_side == 'sell') && (order_price == buy_price)
      if (order_price != order_books.asks.first.price) || (order_books.asks.first.size != order_size)
        log_status
        return
      end
    end

    update_sell_price(order_price, order_size) if sell?(order_side)
    update_buy_price(order_price, order_size) if buy?(order_side)

    log_status
  end

  def sell_immediatelly
    logger.info("IMMEDIATE SELL IN PROGRESS: buy price:#{buy_price} order books: #{order_books}")
    while true
      cancel
      refresh_order_books
      refresh_balance
      create_ask(true)
      sleep 10
      refresh_orders
      break if !active_order? && ((balance.btc * buy_price) < balance.tmn)
    end
    logger.info("IMMEDIATE SELL DONE")
    notification("IMMEDIATE SELL DONE")
    wait_after_loss if !active_order? && ((balance.btc * buy_price) < balance.tmn)
  end

  def wait_after_loss
    i = 0
    while i < WAIT_AFTER_LOSS
      logger.info("sleeping for #{WAIT_AFTER_LOSS - i} after loss")
      i = i + 1
      sleep 1
    end
  end

  def buy_price
    buy_order = YAML.safe_load(File.read('mm-limit_order.yml'), [Symbol])
    return nil unless buy_order # file is empty

    buy_order[:price].to_f
  end

  def stop_loss_crossed_for?(seconds)
    res = []
    1.upto(seconds) do
      crossed = (buy_price - order_books.bids.first.price > STOP_LOSS_LIMIT) && (buy_price - order_books.asks.first.price > STOP_LOSS_LIMIT/2)
      res.push crossed
      break unless crossed
      sleep 1
      refresh_order_books
      logger.info("STOP LOSS CROSSED for #{order_books}")
      notification("STOP LOSS CROSSED")
    end
    res.all?(true)
  end

  def update_buy_price(order_price, order_size)
    if (bids_price_gap < ACCEPTABLE_BID_GAP)
      if (order_price < order_books.bids.first.price) || (order_price == order_books.bids.first.price && order_size == order_books.bids.first.size) 
        cancel
        refresh_order_books
        create_bid
      end
    else 
      if (order_price == order_books.bids.first.price) || (order_price < order_books.bids[1].price) || (order_price == order_books.bids[1].price && order_size == order_books.bids[1].size)
        cancel
        refresh_order_books
        create_bid
      end
    end
  end

  def update_sell_price(order_price, order_size) 
    if (order_price == order_books.asks.first.price && order_size == order_books.asks.first.size) || (order_price > order_books.asks.first.price)
      cancel
      refresh_order_books
      create_ask(false)
    end
  end

  def log_status
    logger.info("STATUS CHECKED: last buy price: #{buy_price} | #{orders.first['price']}| Bid-> [#{order_books.bids[0].price}:#{order_books.bids[0].size}, #{order_books.bids[1].price}:#{order_books.bids[1].size}] | Ask->[#{order_books.asks[0].price}:#{order_books.asks[0].size}, #{order_books.asks[1].price}:#{order_books.asks[1].size}]")

  end

  def active_order?
    !orders.nil? && !orders.empty? 
  end

  def order_books
    return @order_books if @order_books

    orders = exchange.order_books(symbol: symbol)[symbol]
    raise '403 error' if orders['message'] == 'error'

    @order_books = OrderBook.new(
      bids: [
        OrderBookDetail.new(
          price: orders['bids'].first.first.to_f,
          size: orders['bids'].first[1].to_f
        ),
        OrderBookDetail.new(
          price: orders['bids'][1].first.to_f,
          size: orders['bids'][1][1].to_f
        )
      ],
      asks: [
        OrderBookDetail.new(
          price: orders['asks'].first.first.to_f,
          size: orders['asks'].first[1].to_f
        ),
        OrderBookDetail.new(
          price: orders['asks'][1].first.to_f,
          size: orders['asks'][1][1].to_f
        )
      ]
    )
  end

  def refresh_order_books
    @order_books = false
    order_books
  end

  def balance
    return @balance if @balance

    balance = exchange.get_balance
    @balance = Price.new(balance['fiat_available'].to_f, balance['btc_available'].to_f)
  end

  def refresh_balance
    @balance = false
    balance
  end

  def can_create_order?(params, immediate_sell)
    return true if immediate_sell

    if (params.side == 'sell') && (params.price == order_books.bids.first.price)
      logger.info("CAN NOT CREATE ASK ORDER: best bid:#{order_books.bids.first.price}, my ask: #{params.price}")
      false
    elsif (params.side == 'buy') && (params.price == order_books.asks.first.price)
      logger.info("CAN NOT CREATE BID ORDER: best ask:#{order_books.asks.first.price}, my bid: #{params.price}")
      false
    else
      true
    end
  end

  def create(params:, immediate_sell: false)
    unless MARKET_SIDES.include?(params.side)
      return Result.new(false, 'Side is wrong')
    end
    return unless can_create_order?(params, immediate_sell)
    return if min_or_max_price_crossed?(params)

    data = exchange.create_order(
      symbol: params.symbol,
      side: params.side,
      size: params.size,
      type: params.type,
      price: params.price
    )

    save_order(params)
    message = "#{params.side.upcase} ORDER: #{params.price} | #{data['message'].nil? ? 'ok' : data['message']} #{ ' | bought at: '+buy_price.to_s if sell?(params.side)}"
    logger.info(message)
    notification(message)
  end

  def min_or_max_price_crossed?(params)
    return false if params.side == 'buy' && params.price < MAXIMUM_BID_PRICE
    return false if params.side == 'sell' && params.price > MINIMUM_ASK_PRICE

    logger.info("PRICE MIN OR MAX CROSSED: #{params}")
  end

  def cancel
    if orders.empty?
      logger.info('CANCELLING ORDER FAILED: nothing to cancel')
    end

    orders.each do |order|
      data = exchange.cancel_order(order_id: order['id'])
      logger.info("ORDER CANCELLED: #{data}")
    end
  end

  def orders
    return @orders if @orders
    @orders ||= exchange.orders
  end

  def refresh_orders
    @orders = false
    orders
  end

  def user
    exchange.get_user
  end

  def create_bid
    create(params: bid_params)
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

loop do
  MarketMakerLimit.new(symbol: 'btc-tmn', notification_enabled: true).call
  sleep 0.5
end
