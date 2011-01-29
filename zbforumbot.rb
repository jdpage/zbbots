#!/usr/bin/env ruby

require 'rubygems'
require 'cinch'
require 'feedzirra'
require 'net/http'
require 'uri'
require 'json'

$muted = false
$nick = "INSERT BOT NICK HERE"
$bitly_user = "INSERT USERNAME HERE"
$bitly_api = "INSERT API KEY HERE"

def shorten(url)
	r = Net::HTTP.post_form URI.parse('http://api.bit.ly/v3/shorten'), {
		:longUrl => url,
		:domain => "j.mp",
		:login => $bitly_user,
		:apiKey => $bitly_api
	}
	return JSON[r.body]["data"]["url"]
end

def linkify(text)
	"\037\00302#{text}\037\003"
end

$bot = Cinch::Bot.new do
	configure do |c|
		c.server = "irc.esper.net"
		c.channels = ["#zettabyte"]
		c.nick = $nick
	end
end

threads = []

threads << Thread.new do
	$bot.start
end

threads << Thread.new do
puts "loaded feed"

$feed = Feedzirra::Feed.fetch_and_parse("http://zettabyte.ws/feed.php")

loop do
	$feed = Feedzirra::Feed.update($feed)
	puts "fetched feed, #{$feed.new_entries.length} new items."
	if not $muted and $feed.new_entries.length > 0
		h = $feed.new_entries.first
		msg = "#{h.author} just posted in #{h.title}: #{linkify shorten(h.url.sub("&#38;", "&"))}"
		msg += " (plus #{$feed.new_entries.length - 1} other new posts)" if ($feed.new_entries.length > 1)
		$bot.msg("#zettabyte", msg)
		$feed.new_entries.clear
	end

	sleep(120)
end
end

threads.each do |t|
	t.join
end
