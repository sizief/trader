require 'httparty'
require 'json'
require 'open-uri'
require 'rack'

class Exir
  def initialize(access_token:, test: true)
    raise "access token is not provided" if access_token.nil?

    @uri = URI.parse(test ? "https://api.testnet.exir.io/v0" : "https://api.exir.io/v0")
    @header = {
      'Authorization' => "Bearer #{access_token}",
      'Content-Type'=> 'application/json',
      'Accept' => 'application/json',
      'Accept-Language' => 'zh-CN',
      'User-Agent'=> 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36'
      }
  end
  
  def last_price(symbol:)
    path = "/ticker"
    request_method = "GET"
    params ={'symbol'=>symbol}
    util(path,params,request_method)
  end
  
  def get_user
    path = "/user"
    request_method = "GET"
    params ={}
    util(path,params,request_method)
  end
  
  def get_balance
    path = "/user/balance"
    request_method = "GET"
    params ={}
    util(path,params,request_method)
  end
  
  def orders
    path = "/user/orders"
    request_method = "GET"
    params ={}
    util(path,params,request_method)
  end
  
  def cancel_order(order_id:)
    path = "/user/orders"
    request_method = "DELETE"
    params ={'orderId'=>order_id}
    util(path,params,request_method)
  end
  
  def create_order(symbol:, side:, size:, type:, price:)
    path = "/order"
    request_method = "POST"
    params = {
      'symbol'=>symbol,
      'side'=>side,
      'size'=>size,
      'type'=>type,
      'price'=>price
    }
    util(path,params,request_method)
  end
  
  def order_books(symbol:)
    path = "/orderbooks"
    request_method = "GET"
    params = {
      'symbol'=>symbol,
    }
    util(path,params,request_method)
  end
  private

  def util(path,params,request_method)
    url = "#{@uri}#{path}?#{Rack::Utils.build_query(params)}"
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = true
    begin
      JSON.parse http.send_request(request_method, url, JSON.dump(params),@header).body
    rescue Exception => e
      {"message" => 'error' ,"request_error" => e.message}
    end
  end

end
