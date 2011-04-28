#!/usr/bin/env ruby

# Copyright 2011 Jonathan D. Page and Joe Haley. All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification, are
# permitted provided that the following conditions are met:
# 
#    1. Redistributions of source code must retain the above copyright notice, this list of
#       conditions and the following disclaimer.
# 
#    2. Redistributions in binary form must reproduce the above copyright notice, this list
#       of conditions and the following disclaimer in the documentation and/or other materials
#       provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY JONATHAN D. PAGE AND JOE HALEY ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL JONATHAN D. PAGE OR
# JOE HALEY OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
# OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'rubygems'
require 'cinch'
require 'cinch/plugins/identify'
require 'feedzirra'
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'sequel'

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

def dice_roll m, str
	puts str
	if str =~ /^(\d+)d(\d+)([+-]\d*)?$/
		n = $1.to_i
		d = $2.to_i
		s = $3.to_i
		sum = rand(d * n - n + 1) + n + s
		m.channel.send "#{m.user.nick} rolls a #{sum}!"
	elsif str == "cigarette"
		m.channel.send "Roll your own, #{m.user.nick}"
	else
		m.channel.action "thinks that #{m.user.nick} has messed up the syntax."
	end
end

class ForumBot
	def initialize server, channels, nick, username, password = nil
		@server = server
		@channels = channels
		@nick = nick
		@password = password
		@username = username
		
		@bot = Cinch::Bot.new do
			configure do |c|
				c.server = server
				c.channels = channels
				c.nick = nick
				c.plugins.plugins = [Cinch::Plugins::Identify]
				c.plugins.options[Cinch::Plugins::Identify] = {
					:username => username,
					:password => password,
					:type => :nickserv
				}
			end

			on :message, /^\?safety dance/ do |m|
				m.channel.action "does the safety dance with #{m.user.nick}"
			end

			on :message do |m|
				$logger.log m
			end

			on :message, /^\?roll (.*)$/ do |m, roll|
				dice_roll m, roll
			end

			on :private, /^shorten (.+) (.+)$/ do |m, channel, url|
				if url == "" or channel == "" or not url or not channel
					m.user.send "syntax: shorten <channel> <url>"
				end
				short = $shortener.shorten url
				Channel(channel).send "#{m.user} posted a link: #{short}"
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
	def initialize fbot, feed_url, delay, multi_post_url, bitly = nil, ignore
		@fbot = fbot
		@latest = Time.now
		@feed = Feedzirra::Feed.fetch_and_parse(feed_url)
		@bitly = bitly
		@multi_post_url = multi_post_url
		@delay = delay
		@ignore = ignore
	end
	
	def start
		loop do
			begin
				puts "Updating feed..."
				@feed = Feedzirra::Feed.update(@feed)
				entries = parse_entries @feed
				puts "Updated. #{entries.length}/#{@feed.new_entries.length} new/total entries."
				@feed.new_entries.clear
				
				if entries.length > 0
					puts "Sending a message..."
					mesg = build_message(entries)
					@fbot.msg mesg if mesg
				end
				
				sleep(@delay)
			rescue StandardError => err
				puts "Exception in feed thread: " + err.to_s
				return # drop to fix.
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
		return title.sub(/\A.+? [^a-zA-Z0-9?!()\[\]{}\"\' ] /, "")
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
			if @ignore.index(e.author)
				puts "Ignored post by #{e.author}"
				return nil
			end
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

class ChatLog
	def initialize db
		@messages = db[:messages]
		@users = db[:users]
	end

	def user authname
		authname = "" if not authname

		if @users.select(:id).filter(:nickserv => authname).count == 0
			@users.insert(:nickserv => authname)
		end

		return @users.select(:id).filter(:nickserv => authname).first[:id]
	end

	def log m
		@messages.insert(:time => Time.now,
				 :text => m.message, 
				 :nick => m.user.nick,
				 :user => user(m.user.authname))
	end

	def guess nick
		# nick is probably the same as the username
		uid = @users.select(:id).filter(:nickserv => nick).first[:id]
		return uid if uid
		best = nil
		nbest = -1
		@messages.distinct(:user).filter(:nick => nick).each do |u|
			n = @messages.select(:count.sql_function(:id)).filter(:nick => nick, :user => u).first.to_a[0][1]
			if n > nbest
				best = u
				nbest = n
			end
		end
		return best
	end
end

yml = YAML::load(File.open('zbforumbot.yaml'))

db = Sequel.sqlite(yml["local"]["database"]);

$logger = ChatLog.new db

$url_shortener = Bitly.new(yml["bitly"]["user"], yml["bitly"]["apikey"])

forum_bot = ForumBot.new(yml["irc"]["server"], yml["irc"]["channels"], yml["irc"]["nick"], yml["irc"]["user"], yml["irc"]["password"])

threads = []

# IRC Bot Thread
threads << Thread.new do
	forum_bot.start
end

# Feed Reader Thread
threads << Thread.new do
	loop do
		puts "Building new feedreader!"
		feed_reader = FeedMessager.new(forum_bot, yml["feed"]["url"], yml["feed"]["timeout"], yml["feed"]["multilink"], $url_shortener, yml["admin"]["ignore"])
		begin
			feed_reader.start
		rescue Exception => e
			puts "error outside feedreader! #{e.to_s}"
		end
	end
end

threads.each do |t|
	t.join
end
