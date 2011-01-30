#!/usr/bin/env ruby

require 'rubygems'
require 'cinch'
require 'feedzirra'
require 'net/http'
require 'uri'
require 'json'

IRCColorPrefix = "\u0003"

def linkify(text)
	"\037\00302#{text}\037\003"
end

class Bitly
	def initialize user, key
		@user = user
		@key = key
	end
	
	def shorten url
		request = Net::HTTP.post_form URI.parse('http://api.bit.ly/v3/shorten'), {
			:longUrl => url,
			:domain => "j.mp",
			:login => @user,
			:apiKey => @key
		}
		
		return JSON[request.body]["data"]["url"]
	end
end

class ForumBot
	def initialize server, channels, nick, password = nil
		@server = server
		@channels = channels
		@nick = nick
		@password = password
		
		@bot = Cinch::Bot.new do
			configure do |c|
				c.server = server
				c.channels = channels
				c.nick = nick
			end
		end
	end
	
	def nick
		return @bot.nick
	end
	
	def msg msg
		@channels.each do |chan|
			@bot.msg(chan, msg)
		end
	end
	
	def start
		@bot.start
	end
end

#http://zettabyte.ws/search.php?search_id=unreadposts
class FeedMessager
	def initialize fbot, feed_url, delay, multi_post_url, bitly = nil
		@fbot = fbot
		@latest = Time.now
		@feed = Feedzirra::Feed.fetch_and_parse(feed_url)
		@bitly = bitly
		@multi_post_url = multi_post_url
		@delay = delay
	end
	
	def start
		loop do
			begin
				puts "Updating feed..."
				@feed = Feedzirra::Feed.update(@feed)
				entries = parse_entries @feed
				puts "Updated. #{entries.length}/#{@feed.new_entries.length} new/total entries."
				@feed.new_entries.clear
				
				if not @fbot.muted? and entries.length > 0
					puts "Sending a message..."
					@fbot.msg build_message(entries)
				end
				
				sleep(@delay)
			rescue StandardError => err
				puts "Exception in feed thread: " + err
			end
		end
	end
	
	private
	def parse_entries feed
		entries = []
		
		new_time = @latest
		feed.new_entries.each do |e|
			t = Time.parse(e.updated)
			
			if t > @latest
				entries.push e
				
				if t > new_time
					new_time = t
				end
			end
		end
		@latest = new_time
		
		return entries
	end
	
	def fix_title title
		return title.sub(/\A.+ [^a-zA-Z0-9?! ] /, "")
	end
	
	def do_url url
		url = url.sub("&#38;", "&")
		
		if @bitly != nil
			url = @bitly.shorten url
		end
		
		return url
	end
	
	def build_message entries
		msg = IRCColorPrefix + "5"
		
		if entries.length == 1
			e = entries.first
			msg += "#{e.author} posted in #{e.categories[0]} - #{fix_title e.title}"
			url = do_url e.url
		else
			msg += "There have been #{entries.length} new posts"
			url = do_url @multi_post_url
		end
		
		msg += " (#{linkify url}" + IRCColorPrefix + "5)"
		
		return msg
	end
end

url_shortener = Bitly.new("USERNAME", "APIKEY")

forum_bot = ForumBot.new("irc.esper.net", ["#zettabyte-test"], "testbot")

feed_reader = FeedMessager.new(forum_bot, "http://zettabyte.ws/feed.php", 30, "http://zettabyte.ws/search.php?search_id=unreadposts", url_shortener)

threads = []

# IRC Bot Thread
threads << Thread.new do
	forum_bot.start
end

# Feed Reader Thread
threads << Thread.new do
	feed_reader.start
end

threads.each do |t|
	t.join
end
