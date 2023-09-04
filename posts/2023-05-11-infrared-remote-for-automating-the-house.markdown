---
title: Infrared Remote For Automating The iiuhouse
tags: smarthome
wip: true
---

<!--toc:start-->
- [Final Product](#final-product)
- [But... Why?](#but-why)
- [So, What Can It Do?](#so-what-can-it-do)
  - [Control What's Playing On The TV](#control-whats-playing-on-the-tv)
  - [Control Other Stuff](#control-other-stuff)
<!--toc:end-->

Or how I automated quite a few annoying steps with an infrared receiver, an infrared emitter, a
ESP32 micro-controller, [ESPHome](https://esphome.io/) and [Home
Assistant](https://www.home-assistant.io/).

# Final Product

Under the TV sits the following apparatus:

<img src="/images/IR-remote-with-connectors.jpg" />

- **D1 Mini ESP 12F**: runs ESPHome.
- **Power In**: powers the D1 Mini.
- **IR Receiver**: listens for TV remote commands.
- **IR Sender**: sends commands to the TV.
- **TV Power On Sensor**: tells the D1 Mini if the TV is on or off.

Not shown: a server running Home Assistant.

Here's a closeup:

<img src="/images/IR-remote-closeup-with-connectors.jpg" />

# But... Why?

It all started innocently by wanting to have a smart TV remote controller. My TV is not a smart TV.
Hell, it doesn't even have [HDMI CEC](https://en.wikipedia.org/wiki/Consumer_Electronics_Control).
And I have a Google Chromecast, a Raspberry PI running Jellyfin and a few game consoles connected to
it. A typical session is:

1. Turning on TV.
2. Choosing the correct input, depending on if I want to watch a YouTube video, a movie or play a
   game. This requires from 2 to 4 commands with the TV remote.
3. Turning off music in the room using the Sonos app.
4. Opening the correct app on my phone to either cast to Chromecast or to control Jellyfin
   (remember, no HDMI CEC).

The thing is, I usually hate using apps on my phone to control things in the real world and even
more if I need to switch between multiple apps. Nothing replaces physical buttons in my opinion.

# So, What Can It Do?

I control several apparatus by using the following buttons on my TV remote:

## Control What's Playing On The TV

Assuming the TV is off and music is playing in the room, if I cast a YouTube video to the Chromecast
or start playing a movie on Jellyfin:

1. the music will stop playing,
2. the TV will turn on,
3. and the Chromecast or Jellyfin input on the TV will be selected.

If a YouTube video is playing on the Chromecast (or a movie on Jellyfin) and the TV is on and then I
start playing a movie on Jellyfin (or a YouTube video):

1. the Chromecast will stop playing
2. and the TV will switch to the input for Jellyfin (or the Chromecast).

The play, pause, rewind, forward, stop buttons control either Jellyfin or Chromecast depending in
the TV input.

To play a game, the input can be selected by pressing the remote's "1" button. Actually, pressing
"2" will choose the Chromecast input and "3" the Jellyfin input.

## Control Other Stuff

It goes further than controlling the TV!

When the TV is powered down, the remote's play, pause, stop, volume up, volume down and mute buttons
control the music playing in the room.
