require_relative 'huobi.rb'
require 'dotenv/load'
require 'yaml'

class App

  SEED_BITCOIN = 0
  TRADE_FEE = 0.002
  DELAY_AFTER_SELL = 30 #wait 30 seconds after sale

  def initialize(seed_money: 100,big_period_ma:, small_period_ma:, stop_loss_limit: 0.1, ma_gap: 1)
    access_key = ENV['HUOBI_ACCESS_KEY']
    secret_key = ENV['HUOBI_SECRET_KEY']
    account_id = ENV['HUOBI_ACCOUNT_ID']
    @seed_money = seed_money
    @huobi_pro = HuobiPro.new(access_key,secret_key,account_id)
    @big_period_ma = big_period_ma.to_i
    @small_period_ma = small_period_ma.to_i
    @prices = create_array(amount: @big_period_ma, value: 0)
    @money = seed_money
    @bitcoin = SEED_BITCOIN
    @trends = create_array(amount: 30, value: :bear)
    @position_active = false
    @pause_after_sale = false
    @stop_loss_limit = stop_loss_limit
    @ma_gap = ma_gap
  end

  def create_array(amount:, value:)
    array = []
    (1..amount).each { |i| array.push(value)}
    array
  end

  def ready?
    @prices[-@big_period_ma] != 0
  end

  def trade(time, price)
    unless ready?
      puts "#{(@prices.select{|x| x!=0}.count)*100/@big_period_ma}% << #{@prices.last} "
      return
    end

    update_trend
    return if pause_after_sale

    buy if !@position_active && trend_bull?

    # Sell if position and profitable? or under bad loss
    sell if @position_active && profitable? && price_decresing?
    sell if @position_active && stop_loss?
  end

  def pause_after_sale
    return false if @sell_time.nil?

    @sell_time + DELAY_AFTER_SELL > Time.now
  end

  def price_decresing?
    (@prices[-1] < @prices[-2]) && (@prices[-2] < @prices[-3]) && (@prices[-3] < @prices[-4])
  end

  def stop_loss?
    @buy_amount - current_money > (@buy_amount * @stop_loss_limit)
  end

  def profitable?
    current_money - @buy_amount > (@buy_amount * 0.002) 
  end

  def trend_bull?
    @trends[-3..-1].all? (:bull)
     #@trends.last == :bull
  end

  def trend_bear?
    @trends[-3..-1].all? (:bear)
     #@trends.last == :bear
  end

  def buy
    @position_active = true #if success on buy api
    @bitcoin = @money.to_f/@prices.last
    @bitcoin = @bitcoin - (@bitcoin*TRADE_FEE*2)
    @buy_price = @prices.last
    @buy_amount = @money.to_f
    @money = 0
    log "buy at: #{@buy_price}, #{@trends.last}, #{current_money}, BUY, #{Time.now}"
  end

  def sell
    @position_active = false #if success on sell api
    @money = @bitcoin * @prices.last
   # @money = @money - (@money*TRADE_FEE)
    @bitcoin = 0
    @buy_amount = 0
    @sell_time = Time.now
    log "bought: #{@buy_price}, sell at: #{@prices.last}, #{@trends.last}, #{current_money}, SELL, #{Time.now}"
  end

  def update_small_ma
    start = -@small_period_ma
    finish = -1
    price_range = @prices[start..finish]
    @small_ma = price_range.inject(:+).to_f/price_range.count
  end

  def update_big_ma
    start = -@big_period_ma
    finish = -1
    price_range = @prices[start..finish]
    @big_ma = price_range.inject(:+).to_f/price_range.count
  end

  def update_ma
    update_small_ma
    update_big_ma
  end

  def update_trend
    update_ma
    if (@small_ma > @big_ma) && (@small_ma-@big_ma > @ma_gap)
      @trends.push :bull
      @trends.shift
    elsif (@big_ma > @small_ma) && (@big_ma-@small_ma > @ma_gap)
      @trends.push :bear
      @trends.shift
    else
      @trends.push :peace
      @trends.shift
    end
  end

  def log(text)
    open("ticks_#{ARGV[0]}.log", 'a') do |f|
      f << text+"\n"
    end
  end

  def current_money
    return @money unless @money == 0
    @bitcoin * @prices.last
  end

  def update_price_history(price)
    @prices.push(price)
    @prices.shift
  end

  def call
    while true do
      last_trade = @huobi_pro.market_trade('btcusdt')
      next if last_trade.nil? || last_trade['tick'].nil? || last_trade['tick']['data'].nil?

      last_tick = last_trade['tick']['data'].first

      update_price_history(last_tick['price'])

      trade(last_tick['ts'], last_tick['price']) 

      sleep 0.3
      log "#{@trends.last} | #{@prices.last} | #{current_money} #{@position_active ? ' | '+ARGV[0]+': '+@buy_price.to_s : ''}" if ready?
    end
  end
end


startegies = YAML.load_file('strategies.yml')
params =  startegies[ARGV[0]]
abort if params.nil?

App.new(
  seed_money: params["seed_money"],
  big_period_ma: params["big_period_ma"],
  small_period_ma: params["small_period_ma"],
  stop_loss_limit: params["stop_loss_limit"],
  ma_gap: params["ma_gap"]
).call

