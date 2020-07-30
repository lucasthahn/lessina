# Lessina

Realtime vocal (or otherwise) harmonization without having to buy an Eventide H800.

Here's how we make this happen:

  1. Access raw input signals using `JUCE`
  2. Use pitch detection to approximate nearest pitch
  3. Pitch correct
  4. Implement pitch-shifting algorithm
  5. Map pitch-shifting to MIDI

Some open questions/comments:

  - Need to make it sound like a soulful robot - the goal is not to replicate a human choir but for this to be a vibe in itself
  - The V0 version of this probably doesn't mess around with pitch correction at all and you just run auto-tuned vocals into it
  - Make a Julia wrapper for JUCE?

# Building RTAudio Library

Might need to use `RTAudio` in order to not muck around deep in the low-level weeds of `CoreAudio`.

If building `RTAudio` on C++11 or higher will run into deprecation errors. To bypass do:

```
cd extern/rtaudio
chmod 777 autogen.sh && ./autogen.sh
sed '345s/$/ -Wno-deprecated-register/' Makefile
```
