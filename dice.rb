require 'rubygems'
require 'cinch'

class Dice
	include Cinch::Plugin

	match /roll (\d.)d(\d+)([+-]\d+)?/

	def execute m, num, sides, diff
		n = num.to_i
		n = 1 if num == ""
		d = sides.to_i
		s = diff.to_i
		sum = rand(d * n - n + 1) + n + s
		m.reply "#{m.user.nick} rolls a #{sum}!"
	end
end
