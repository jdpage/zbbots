require 'rubygems'
require 'cinch'
require 'open-uri'
require 'hpricot'

class LinkTitles
	include Cinch::Plugin

	match /http:\/\/.+?(?=\s|$)/

	def execute(m, url)
		m.channel.send "title of #{url} is #{LinkTitles.fetch_title url}"
	end

	def self.fetch_title url
		response = ''
		open(url, "User-Agent" => "Ruby/#{RUBY_VERSION}") do |f|
			response = f.read
		end
		doc = Hpricot(response)

		return (doc/"/html/head/title").inner_html
	end
end
