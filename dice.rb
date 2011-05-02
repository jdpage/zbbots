require 'rubygems'
require 'cinch'

class Dice
	include Cinch::Plugin

	match /roll (\d*)d(\d+)([+-]\d+)?/
	prefix /^\?/

	def execute m, num, sides, diff
		n = num.to_i
		n = 1 if num == ""
		d = sides.to_i
		s = diff.to_i
		# sum = rand(d * n - n + 1) + n + s
		if n > 50
			m.reply "only rolling 50 dice"
			n = 50
		end
		sum = s
		n.times { sum += rand(d) + 1 }
		m.reply "#{m.user.nick} rolls a #{sum}!"
	end
end
