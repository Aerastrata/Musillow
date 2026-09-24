package com.lthirius.music_app

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (from just_audio_background's audio_service dependency)
// wires up the correct FlutterEngine for the foreground media service, which
// keeps playback alive with the screen off.
class MainActivity : AudioServiceActivity()
