require 'httparty'
require 'json'
require 'open-uri'
require 'rack'
require 'dotenv/load'

class Telegram
  def initialize
    @url = "https://api.telegram.org/bot#{ENV['TELEGRAM_BOT']}/"
    @uri = URI.parse @url
    @header = {
        'Content-Type'=> 'application/json',
        'Accept' => 'application/json'
      }
  end

  def call(path, request_method, params)
    url = "#{@url}#{path}"
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = true
    JSON.parse http.send_request(request_method, url, JSON.dump(params),@header).body
  end

  def get_updates
    call('getUpdates', 'GET', '')
  end

  def send_message(text)
    call('sendMessage', 'POST', {chat_id: ENV['CHAT_ID'], text: text})
  end
end
