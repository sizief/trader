require_relative 'exir'
require 'dotenv/load'

class MarketMaker
  Result = Struct.new(:ok, :message, :data)
  Price = Struct.new(:tmn, :btc)
  OrderParams = Struct.new(:symbol, :size, :side, :price, :type, keyword_init: true)
  OrderBook = Struct.new(:bid,:ask, keyword_init: true)
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
      p 'not empty' #update_price
    else
      (balance.tmn > 20_000) ? create_bid : create_ask
    end
  end

  def active_order?
    !orders.empty?
  end

  def order_books
    return @order_books if @order_books
    orders = exchange.order_books(symbol: symbol)[symbol]

    @order_books = OrderBook.new(
      bid: orders['bids'].first.first.to_f,
      ask: orders['asks'].first.first.to_f
    )
  end

  def balance
    return @balance if @balance

    balance = exchange.get_balance
    @balance = Price.new(balance['fiat_available'].to_f, balance['btc_available'].to_f)
  end

  def create(params)
    return Result.new(false, 'Type is wrong') unless MARKET_SIDES.include?(params.side)

    data =exchange.create_order(
      symbol: params.symbol,
      side: params.side,
      size: params.size,
      type: params.type,
      price: params.price
    )

    logger.info("#{params.side.upcase} BUY ORDER: #{data}")
#    Result.new(true, "Order created", data)
  end

  def cancel
    current_orders = orders
    return Result.new(false, 'Nothing to cancel') if current_orders.empty?

    data = exchange.cancel_order(order_id: current_orders.first['id'])

    Result.new(true, 'Cancelled', data)
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
    bid_price = order_books.bid + PRICE_STEP
    bid_size = (balance.tmn*0.95)/bid_price

    params = OrderParams.new(
      symbol: symbol, 
      size: bid_size,
      side: 'buy',
      price: bid_price,
      type: ORDER_TYPE
    )

    logger.info("PREPARING_BID_ORDER: #{order_books.bid}, #{order_books.ask}, #{balance.tmn}, #{params}")

    params
  end

  def ask_params
    ask_price = order_books.ask - PRICE_STEP
    ask_size = balance.btc

    params = OrderParams.new(
      symbol: symbol, 
      size: ask_size,
      side: 'sell',
      price: ask_price,
      type: ORDER_TYPE
    )

    logger.info("PREPARING_BID_ORDER: #{order_books.bid}, #{order_books.ask}, #{balance.btc}, #{params}")

    params
  end
end

mm = MarketMaker.new(symbol: 'btc-tmn')
mm.call
mm.call
mm.call
mm.call
abort

#result = mm.create(symbol: symbol, side: 'buy', size: bid_size, price: bid_price)
#logger.info("ORDER_CREATED: #{result.data}")

result = mm.cancel
logger.info("ORDER_CANCELLED: #{result.message}, #{result.data}")


