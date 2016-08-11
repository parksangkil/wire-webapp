#
# Wire
# Copyright (C) 2016 Wire Swiss GmbH
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see http://www.gnu.org/licenses/.
#

window.z ?= {}
z.audio ?= {}

AUDIO_PATH = '/audio'

# Audio repository for all audio interactions.
class z.audio.AudioRepository
  # Construct a new Audio Repository.
  constructor: ->
    @logger = new z.util.Logger 'z.audio.AudioRepository', z.config.LOGGER.OPTIONS

    @audio_context = undefined
    @sounds = {}

    @in_loop = {}

    @_init_sounds()
    @_subscribe_to_audio_events()
    @_subscribe_to_audio_properties()

  # Closing the AudioContext.
  close_audio_context: =>
    if @audio_context
      @audio_context.close()
      @audio_context = undefined
      @logger.log @logger.levels.INFO, 'Closed existing AudioContext'

  # Initialize the AudioContext.
  get_audio_context: =>
    if @audio_context
      @logger.log @logger.levels.INFO, 'Reusing existing AudioContext', @audio_context
      return @audio_context
    else if window.AudioContext
      @audio_context = new window.AudioContext()
      @logger.log @logger.levels.INFO, 'Initialized a new AudioContext', @audio_context
      return @audio_context
    else
      @logger.log @logger.levels.ERROR, 'The flow audio cannot use the Web Audio API as it is unavailable.'
      return undefined

  # Preload all sounds for immediate playback.
  preload: =>
    @logger.log @logger.levels.INFO, 'Pre-loading audio files for immediate playback'
    sound.load() for id, sound of @sounds

  ###
  Get the sound object
  @param audio_id [z.audio.AudioType] Sound identifier
  ###
  _get_sound: (audio_id) =>
    new Promise (resolve, reject) =>
      if @sounds[audio_id]
        resolve @sounds[audio_id]
      else
        reject new z.audio.AudioError 'Audio not found', z.audio.AudioError::TYPE.AUDIO_NOT_FOUND

  ###
  Initialize all sounds.
  @private
  ###
  _init_sounds: ->
    @sounds =
      "#{z.audio.AudioType.ALERT}": new Audio "#{AUDIO_PATH}/alert.mp3"
      "#{z.audio.AudioType.CALL_DROP}": new Audio "#{AUDIO_PATH}/call_drop.mp3"
      "#{z.audio.AudioType.NETWORK_INTERRUPTION}": new Audio "#{AUDIO_PATH}/nw_interruption.mp3"
      "#{z.audio.AudioType.NEW_MESSAGE}": new Audio "#{AUDIO_PATH}/new_message.mp3"
      "#{z.audio.AudioType.OUTGOING_PING}": new Audio "#{AUDIO_PATH}/ping_from_me.mp3"
      "#{z.audio.AudioType.INCOMING_PING}": new Audio "#{AUDIO_PATH}/ping_from_them.mp3"
      "#{z.audio.AudioType.READY_TO_TALK}": new Audio "#{AUDIO_PATH}/ready_to_talk.mp3"
      "#{z.audio.AudioType.OUTGOING_CALL}": new Audio "#{AUDIO_PATH}/ringing_from_me.mp3"
      "#{z.audio.AudioType.INCOMING_CALL}": new Audio "#{AUDIO_PATH}/ringing_from_them.mp3"
      "#{z.audio.AudioType.TALK_LATER}": new Audio "#{AUDIO_PATH}/talk_later.mp3"

  ###
  Start playback of a sound
  @private
  @param audio_id [z.audio.AudioType] Sound identifier
  ###
  _play: (audio_id) ->
    return if @sound_setting() is z.audio.AudioSetting.NONE and audio_id not in z.audio.AudioPlayingType.NONE
    return if @sound_setting() is z.audio.AudioSetting.SOME and audio_id not in z.audio.AudioPlayingType.SOME

    @_get_sound audio_id
    .then (audio) =>
      if audio.paused
        @logger.log @logger.levels.INFO, "Playing sound '#{audio_id}'", audio
        audio.currentTime = 0 if audio.currentTime isnt 0
        audio.loop = false
        audio.play()
    .catch (error) =>
      @logger.log @logger.levels.ERROR, "Failed playing sound '#{audio_id}': #{error.message}", audio

  ###
  Start playback of a sound in a loop.
  @private
  @note Prevent playing multiples instances of looping sounds
  @param audio_id [z.audio.AudioType] Sound identifier
  ###
  _play_in_loop: (audio_id) ->
    return if @sound_setting() is z.audio.AudioSetting.NONE and audio_id not in z.audio.AudioPlayingType.NONE
    return if @sound_setting() is z.audio.AudioSetting.SOME and audio_id not in z.audio.AudioPlayingType.SOME

    @_get_sound audio_id
    .then (audio) =>
      if audio.paused
        @logger.log @logger.levels.INFO, "Looping sound '#{audio_id}'", audio
        @in_loop[audio_id] = audio_id
        audio.currentTime = 0 if audio.currentTime isnt 0
        audio.loop = true
        audio.play()
      else
        @logger.log @logger.levels.WARN, "Sound '#{audio_id}' is already looping", audio
    .catch (error) =>
      @logger.log @logger.levels.ERROR, "Failed looping sound '#{audio_id}': #{error.message}", audio

  ###
  Stop playback of a sound.
  @private
  @param audio_id [z.audio.AudioType] Sound identifier
  ###
  _stop: (audio_id) ->
    @_get_sound audio_id
    .then (audio) =>
      if not audio.paused
        @logger.log @logger.levels.INFO, "Stopping sound '#{audio_id}'", audio
        audio.pause()
      delete @in_loop[audio_id] if @in_loop[audio_id]
    .catch (error) =>
      @logger.log @logger.levels.ERROR, "Failed stopping sound '#{audio_id}': #{error.message}", audio

  # Stop all sounds playing in loop.
  _stop_all: ->
    @_stop sound for sound of @in_loop

  # Use Amplify to subscribe to all audio playback related events.
  _subscribe_to_audio_events: ->
    amplify.subscribe z.event.WebApp.AUDIO.PLAY, @, @_play
    amplify.subscribe z.event.WebApp.AUDIO.PLAY_IN_LOOP, @, @_play_in_loop
    amplify.subscribe z.event.WebApp.AUDIO.STOP, @, @_stop

  # Use Amplify to subscribe to all audio properties related events.
  _subscribe_to_audio_properties: ->
    @sound_setting = ko.observable z.audio.AudioSetting.ALL
    @sound_setting.subscribe (sound_setting) =>
      @_stop_all() if sound_setting is z.audio.AudioSetting.NONE

    amplify.subscribe z.event.WebApp.PROPERTIES.UPDATED, (properties) =>
      @sound_setting properties.settings.sound.alerts

    amplify.subscribe z.event.WebApp.PROPERTIES.UPDATE.SOUND_ALERTS, (value) =>
      @sound_setting value
