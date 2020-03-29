require_relative 'exir'
require 'dotenv/load'

class MarketMaker
  Result = Struct.new(:ok, :message, :data)
  Price = Struct.new(:tmn, :btc)
  OrderParams = Struct.new(:symbol, :size, :side, :price, :type, keyword_init: true)
  OrderBook = Struct.new(:bids,:asks, keyword_init: true)
  OrderBookDetail = Struct.new(:price, :size, keyword_init: true)
  MARKET_SIDES = %w(buy sell)
  ORDER_TYPE = 'limit'
  PRICE_STEP = 50_000

  attr_reader :exchange, :symbol, :logger

  def initialize(symbol:, logger: Logger.new('./logfile.log'))
    @exchange = Exir.new(access_token: ENV['EXIR_ACCESS_TOKEN'], test: false)
    @symbol = symbol
    @logger = logger
  end

  def call
    if active_order?
      update_price
    else
      logger.info("CREATING ORDER: available orders: #{orders}")
      (balance.tmn > 50_000) ? create_bid : create_ask
    end
  end

  def update_price
    order_price = orders.first['price'].to_f
    order_side = orders.first['side']
    order_size = orders.first['size']

    if (order_side == 'buy') && (order_price < order_books.bids.first.price)
      cancel
      refresh_order_books
      create_bid
    elsif (order_side == 'buy') && ((order_price - PRICE_STEP) != order_books.bids[1].price) && (order_size == order_books.bids.first.size)
      cancel
      refresh_order_books
      create_bid
    elsif (order_side == 'sell') && (order_price > order_books.asks.first.price)
      cancel
      refresh_order_books
      create_ask
    elsif (order_side == 'sell') && ((order_price + PRICE_STEP) != order_books.asks[1].price) && (order_size == order_books.asks.first.size)
      cancel
      refresh_order_books
      create_ask
    else
      logger.info("STATUS CHECKED: #{orders.first['price']}| Bid-> [#{order_books.bids[0].price}:#{order_books.bids[0].size}, #{order_books.bids[1].price}:#{order_books.bids[1].size}] | Ask->[#{order_books.asks[0].price}:#{order_books.asks[0].size}, #{order_books.asks[1].price}:#{order_books.asks[1].size}]")
    end
  end

  def active_order?
    !orders.nil? && !orders.empty?
  end

  def order_books
    return @order_books if @order_books
    orders = exchange.order_books(symbol: symbol)[symbol]

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

  def can_create_order?(params)
    if (params.side == 'sell') && (params.price == order_books.bids.first.price)
      logger.info("CAN NOT CREATE ASK ORDER: best bid:#{order_books.bids.first.price}, my ask: #{params.price}")
      return false
    elsif (params.side == 'buy') && (params.price == order_books.asks.first.price)
      logger.info("CAN NOT CREATE BID ORDER: best ask:#{order_books.asks.first.price}, my bid: #{params.price}")
      return false
    else
      true
    end
  end

  def create(params)
    return Result.new(false, 'Type is wrong') unless MARKET_SIDES.include?(params.side)
    return unless can_create_order?(params)

    data =exchange.create_order(
      symbol: params.symbol,
      side: params.side,
      size: params.size,
      type: params.type,
      price: params.price
    )

    logger.info("#{params.side.upcase} ORDER: #{data}")
  end

  def cancel
    current_orders = orders
    logger.info("CANCELLING ORDER FAILED: nothing to cancel") if current_orders.empty?

    data =exchange.cancel_order(order_id: current_orders.first['id'])

    logger.info("ORDER CANCELLED: #{data}")
  end

  def orders
    @orders ||= exchange.orders
  end

  def user
    exchange.get_user
  end

  def create_bid
    create(bid_params)
  end

  def create_ask
    create(ask_params)
  end

  def bid_params
    price_step = ((order_books.bids.first.price + PRICE_STEP) == order_books.asks.first.price) ? 0 : PRICE_STEP
    bid_price = order_books.bids.first.price + price_step
    bid_size = (balance.tmn*0.95)/bid_price

    params = OrderParams.new(
      symbol: symbol, 
      size: bid_size,
      side: 'buy',
      price: bid_price,
      type: ORDER_TYPE
    )

    logger.info("PREPARING_BID_ORDER: #{order_books.bids.first.price}, #{order_books.asks.first.price}, #{balance.tmn}, #{params}")

    params
  end

  def ask_params
    price_step = ((order_books.asks.first.price - PRICE_STEP) == order_books.bids.first.price) ? 0 : PRICE_STEP
    ask_price = order_books.asks.first.price - price_step
    ask_size = balance.btc*0.96

    params = OrderParams.new(
      symbol: symbol, 
      size: ask_size,
      side: 'sell',
      price: ask_price,
      type: ORDER_TYPE
    )

    logger.info("PREPARING_ASK_ORDER: #{params}")

    params
  end
end

while true
  MarketMaker.new(symbol: 'btc-tmn').call
  sleep 0.5
end
