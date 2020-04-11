local MidiPlayer = require "WildMidi"

function love.load()
	MidiPlayer.open("fastway.mid", {
			cfgfile = "patches/wildmidi.cfg",
			logarithmicvolume = true,
			enhancedresampling = true,
			reverb = true,
			loop = true
		})
end

local playing = true
function love.keypressed()
	playing = not playing
end

function love.update(dt)
	if playing then
		MidiPlayer.play()
	end
end
