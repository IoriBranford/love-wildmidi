local ffi = require "ffi"
local bit = require "bit"

local ok, lib = pcall(ffi.load, "WildMidi")
if not ok then
	print(lib)
	return
end

ffi.cdef([[
/*
 * wildmidi_lib.h -- Midi Wavetable Processing library
 *
 * Copyright (C) WildMIDI Developers 2001-2016
 *
 * This file is part of WildMIDI.
 *
 * WildMIDI is free software: you can redistribute and/or modify the player
 * under the terms of the GNU General Public License and you can redistribute
 * and/or modify the library under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation, either version 3 of
 * the licenses, or(at your option) any later version.
 *
 * WildMIDI is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License and
 * the GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License and the
 * GNU Lesser General Public License along with WildMIDI.  If not,  see
 * <http://www.gnu.org/licenses/>.
 */

struct _WM_Info {
    char *copyright;
    uint32_t current_sample;
    uint32_t approx_total_samples;
    uint16_t mixer_options;
    uint32_t total_midi_time;
};

typedef void midi;

typedef void * (*_WM_VIO_Allocate)(const char *, uint32_t *);
typedef void   (*_WM_VIO_Free)(void *);

struct _WM_VIO {
    /*
    This function should allocate a buffer which has the size
    of the requested file plus one (size+1), fill the buffer
    with the file content, and the second parameter with the
    size of the file.

    The buffer is in possession of wildmidi until the free_file
    function is called with the buffer address as argument.
    */
    _WM_VIO_Allocate allocate_file;

    /*
    This function should free the memory of the given buffer.
    */
    _WM_VIO_Free free_file;
};

const char * WildMidi_GetString (uint16_t info);
long WildMidi_GetVersion (void);
int WildMidi_Init (const char *config_file, uint16_t rate, uint16_t mixer_options);
int WildMidi_InitVIO(struct _WM_VIO * callbacks, const char *config_file, uint16_t rate, uint16_t mixer_options);
int WildMidi_MasterVolume (uint8_t master_volume);
midi * WildMidi_Open (const char *midifile);
midi * WildMidi_OpenBuffer (uint8_t *midibuffer, uint32_t size);
int WildMidi_GetMidiOutput (midi *handle, int8_t **buffer, uint32_t *size);
int WildMidi_GetOutput (midi *handle, int8_t *buffer, uint32_t size);
int WildMidi_SetOption (midi *handle, uint16_t options, uint16_t setting);
int WildMidi_SetCvtOption (uint16_t tag, uint16_t setting);
int WildMidi_ConvertToMidi (const char *file, uint8_t **out, uint32_t *size);
int WildMidi_ConvertBufferToMidi (uint8_t *in, uint32_t insize,
                                            uint8_t **out, uint32_t *size);
struct _WM_Info * WildMidi_GetInfo (midi * handle);
int WildMidi_FastSeek (midi * handle, unsigned long int *sample_pos);
int WildMidi_SongSeek (midi * handle, int8_t nextsong);
int WildMidi_Close (midi * handle);
int WildMidi_Shutdown (void);
char * WildMidi_GetLyric (midi * handle);

char * WildMidi_GetError (void);
void WildMidi_ClearError (void);


/* NOTE: Not Yet Implemented Or Tested Properly */
/* Due to delay in audio output in the player, this is not being developed
   futher at the moment. Further Development will occur when output latency
   has been reduced enough to "appear" instant.
int WildMidi_Live (midi * handle, uint32_t midi_event);
 */

/* reserved for future coding
 * need to change these to use a time for cmd_pos and new_cmd_pos

int WildMidi_InsertMidiEvent (midi * handle, uint8_t char midi_cmd, *char midi_cmd_data, unsigned long int midi_cmd_data_size, unsigned long int *cmd_pos);
int WildMidi_DeleteMidiEvent (midi * handle, uint8_t char midi_cmd, unsigned long int *cmd_pos);
int WildMidi_MoveMidiEvent (midi * handle, , uint8_t char midi_cmd, unsigned long int *cmd_pos, unsigned long int *new_cmd_pos);
 */
]])

local WM_MO_LOG_VOLUME         =0x0001
local WM_MO_ENHANCED_RESAMPLING=0x0002
local WM_MO_REVERB             =0x0004
local WM_MO_LOOP               =0x0008
local WM_MO_SAVEASTYPE0        =0x1000
local WM_MO_ROUNDTEMPO         =0x2000
local WM_MO_STRIPSILENCE       =0x4000
local WM_MO_TEXTASLYRIC        =0x8000

local WM_CO_XMI_TYPE          =0x0010
local WM_CO_FREQUENCY         =0x0020

local WM_GS_VERSION           =0x0001

local midi = nil

local source, sounddata

local function Shutdown()
	if midi then
		lib.WildMidi_Close(midi)
		lib.WildMidi_Shutdown()
		midi = nil
	end
end

local MidiPlayer = {}

function MidiPlayer.play()
	if source:getFreeBufferCount() > 0 then
		local r = lib.WildMidi_GetOutput(midi, sounddata:getFFIPointer(),
			sounddata:getSize())
		if r < 0 then
			print(lib.WildMidi_GetError())
		end
		source:queue(sounddata)
		source:play()
	end
end

local callbacks = ffi.new("struct _WM_VIO")
callbacks.allocate_file = function(filename, filesize)
	local data, size = love.filesystem.read("data", ffi.string(filename))
	if not data then
		print(size)
		return nil
	end
	filesize[0] = size
	return data:getFFIPointer()
end
callbacks.free_file = function()
end

function MidiPlayer.open(filename, options)
	local data, error = love.filesystem.newFileData(filename)
	if not data then
		print(error)
		return nil
	end

	options = options or {}
	local rate = options.rate or 44100

	local cfgfile = options.cfgfile or "wildmidi.cfg"

	local bitoptions = 0
	if options.logarithmicvolume then
		bitoptions = bit.bor(bitoptions, WM_MO_LOG_VOLUME)
	end
	if options.enhancedresampling then
		bitoptions = bit.bor(bitoptions, WM_MO_ENHANCED_RESAMPLING)
	end
	if options.reverb then
		bitoptions = bit.bor(bitoptions, WM_MO_REVERB)
	end

	Shutdown()

	if lib.WildMidi_InitVIO(callbacks, cfgfile, rate, bitoptions) ~= 0 then
		print(lib.WildMidi_GetError())
		return nil
	end

	midi = lib.WildMidi_OpenBuffer(data:getFFIPointer(), data:getSize())
	if not midi then
		print(lib.WildMidi_GetError())
		lib.WildMidi_Shutdown()
		return nil
	end

	bitoptions = 0
	if options.loop then
		bitoptions = bit.bor(bitoptions, WM_MO_LOOP)
	end
	lib.WildMidi_SetOption(midi, bitoptions, bitoptions)

	source = love.audio.newQueueableSource(rate, 16, 2)
	local buffersamples = options.buffersamples or 2048
	sounddata = sounddata or love.sound.newSoundData(buffersamples, rate)
	return midi
end

return MidiPlayer
