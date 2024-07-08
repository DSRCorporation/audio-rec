# audio_rec README.md

# Summary

Audio recorder (audio_rec) is an open-source command line recorder utility developed as an
example to demonstrate AUR API (audio recorder API), built in a top of CoreAudio, which
allows a user to record an audio from a process. Now that's does not require to develop
a kernel extensions because in macOS  >=14.4 Apple introduced several new functions in CoreAudio that allows any app to capture audio from other apps or the entire system, as long as the user has given the app permission to do so.

# Prerequisites

1. You need to have a macOS based computer with macOS >= 14.4.
2. You need to install latest XCode with command line tools package.
3. You need to install recent cmake.

# How to build

Navigate to downloaded project folder.

```
mkdir build
cmake -S . -B build
cmake --build build --config Release
```

# How to use

Get at first all process pids from which the audio recording is allowed:

```
./build/audio_rec -l

15990 AudioTapSample
460 ContinuityCaptureAgent
506 Control Centre
497 Control Strip
7562 Music
28184 Podcasts
5270 PowerChime
523 QuickLookUIService (PID 510)
27914 QuickTime Player
14904 REAPER
830 Realphones
467 Safari
757 Safari Graphics and Media
478 Terminal
7570 VOX
797 ZoomClips
336 aceagent
605 assistantd
29565 audio_rec
591 avconferenced
477 callservicesd
799 caphost
805 corespeechd
539 heard
178 loginwindow
10332 tipsd
454 universalaccessd
504 zoom.us
798 zoom.us Graphics and Media

```

Then record an audio from a desired process. For example for Safari:

```
 ./build/audio_rec -p 757 .
```
When the recording is stopped you'll get a recorded file with the 
name like pid-757-recording-8_Jul_2024_at_17-35-55.caf in your current folder.

