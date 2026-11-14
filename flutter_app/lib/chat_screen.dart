import 'ui_text.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'app_controller.dart';
import 'api.dart';
import 'models.dart';
import 'screens.dart';
import 'theme_compat.dart';

class ChatScreen extends StatefulWidget {
  final AppController controller;
  const ChatScreen({super.key, required this.controller});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final composer = TextEditingController();
  final scroll = ScrollController();
  final recorder = AudioRecorder();
  final player = AudioPlayer();
  final chunks = BytesBuilder(copy: false);
  final recordingWatch = Stopwatch();
  StreamSubscription<Uint8List>? recordingSubscription;
  Timer? recordingTimer;
  bool recording = false, audioBusy = false, preparingMic = false;
  String? audioError;
  int lastCount = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(changed);
  }

  void changed() {
    if (!mounted) {
      return;
    }
    if (widget.controller.tab != 1) {
      player.pause();
      if (recording) {
        stopRecording(transcribe: false);
      }
    }
    if (lastCount != widget.controller.messages.length ||
        widget.controller.chatting) {
      lastCount = widget.controller.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent,
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: Curves.easeOut);
        }
      });
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      player.pause();
      if (recording) {
        stopRecording(transcribe: false);
      }
    }
  }

  @override
  void dispose() {
    if (!audioBusy) widget.controller.audioActive = false;
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(changed);
    recordingTimer?.cancel();
    recordingSubscription?.cancel();
    recorder.dispose();
    player.dispose();
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> record() async {
    if (widget.controller.demo) {
      setState(() {
        audioError = UiText.get(widget.controller.appLanguage, 'demoMic');
      });
      return;
    }
    if (recording) {
      await stopRecording();
      return;
    }
    if (preparingMic ||
        audioBusy ||
        widget.controller.audioActive ||
        widget.controller.chatting ||
        widget.controller.languagesSaving) {
      return;
    }
    widget.controller.setAudioActive(true);
    setState(() {
      preparingMic = true;
      audioError = null;
    });
    try {
      if (!await recorder.hasPermission()) {
        throw ApiFailure(
            UiText.get(widget.controller.appLanguage, 'micPermission'));
      }
      if (!mounted) {
        return;
      }
      chunks.clear();
      final stream = await recorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
      if (!mounted) {
        await recorder.stop();
        return;
      }
      recordingSubscription = stream.listen(chunks.add,
          onError: (Object error) {
        if (mounted) {
          setState(() {
            audioError =
                UiText.get(widget.controller.appLanguage, 'recordingFailed');
          });
          stopRecording(transcribe: false);
        }
      }, onDone: () {
        if (mounted && recording) stopRecording(transcribe: false);
      });
      setState(() {
        recording = true;
      });
      recordingWatch
        ..reset()
        ..start();
      recordingTimer = Timer(const Duration(seconds: 15), stopRecording);
    } catch (e) {
      if (mounted) {
        setState(() {
          audioError = e is ApiFailure
              ? e.message
              : UiText.get(widget.controller.appLanguage, 'micFailed');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          preparingMic = false;
        });
        widget.controller.setAudioActive(recording || audioBusy);
      }
    }
  }

  Future<void> stopRecording({bool transcribe = true}) async {
    if (!recording) {
      return;
    }
    recordingTimer?.cancel();
    recordingWatch.stop();
    setState(() {
      recording = false;
      audioBusy = transcribe;
    });
    widget.controller.setAudioActive(transcribe);
    try {
      await recorder.stop();
      await recordingSubscription?.cancel();
      recordingSubscription = null;
      final bytes = chunks.takeBytes();
      if (!transcribe || bytes.isEmpty) {
        return;
      }
      if (widget.controller.demo) {
        throw ApiFailure(UiText.get(widget.controller.appLanguage, 'demoMic'));
      }
      // On the web, the OS/browser may ignore a requested 16 kHz input and
      // stream PCM at its native rate (commonly 48 kHz). Infer that rate from
      // the received frames, so the WAV duration remains truthful server-side.
      final sampleRate = pcmSampleRate(bytes, recordingWatch.elapsed);
      final text = await widget.controller.api
          .transcribe(widget.controller.profileId, pcmToWav(bytes, sampleRate: sampleRate));
      if (mounted) {
        composer.text = text;
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          audioError = e is ApiFailure
              ? e.message
              : UiText.get(
                  widget.controller.appLanguage, 'transcriptionFailed');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          audioBusy = false;
        });
      }
      widget.controller.setAudioActive(false);
    }
  }

  Future<void> speak(String text) async {
    if (audioBusy ||
        recording ||
        widget.controller.audioActive ||
        widget.controller.languagesSaving) {
      return;
    }
    if (widget.controller.demo) {
      setState(() {
        audioError = UiText.get(widget.controller.appLanguage, 'demoSpeech');
      });
      return;
    }
    final session = widget.controller.sessionId;
    if (session == null) {
      return;
    }
    widget.controller.setAudioActive(true);
    setState(() {
      audioBusy = true;
      audioError = null;
    });
    try {
      final bytes = await widget.controller.api
          .speech(widget.controller.profileId, session, text);
      if (mounted) {
        await player.play(BytesSource(bytes));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          audioError = e is ApiFailure
              ? e.message
              : UiText.get(widget.controller.appLanguage, 'speechFailed');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          audioBusy = false;
        });
      }
      widget.controller.setAudioActive(false);
    }
  }

  void send() {
    final text = composer.text.trim();
    if (text.isEmpty ||
        widget.controller.chatting ||
        widget.controller.pending != null) {
      return;
    }
    composer.clear();
    widget.controller.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cs = Theme.of(context).colorScheme;
    if (!c.configured) {
      return const ConnectionWelcome();
    }
    if (c.messages.isEmpty && !c.chatting && c.chatError == null) {
      return StatusPane(
          icon: Icons.graphic_eq_rounded,
          title: c.tr('chatTitle'),
          message: c.tr('chatHelp'),
          action: c.tr('startChat'),
          onAction: c.startChat);
    }
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(children: [
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 23, vertical: 17),
                  decoration: BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: cs.outlineVariant))),
                  child: Row(children: [
                    Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.graphic_eq_rounded,
                            color: cs.primary, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(c.tr('tutor'),
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(c.tr('tutorHelp'),
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant))
                        ])),
                    if (audioBusy)
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    IconButton(
                        onPressed: player.stop,
                        tooltip: UiText.get(
                            widget.controller.appLanguage, 'stopSpeech'),
                        icon: const Icon(Icons.volume_off_outlined, size: 19))
                  ])),
              if (c.practiceCompleted != null && c.sessionId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(23, 12, 23, 0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            UiText.get(c.appLanguage, 'practiceProgress',
                                params: {
                                  'done': c.practiceCompleted!.clamp(0, 8),
                                  'total': 8
                                }),
                            style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                            value: c.practiceCompleted!.clamp(0, 8) / 8),
                      ]),
                ),
              Expanded(
                child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(23, 25, 23, 25),
                    children: [
                      for (final message in c.messages)
                        MessageBubble(
                            message: message,
                            onSpeak: !audioBusy && !recording
                                ? () => speak(message.text)
                                : null),
                      if (c.chatting)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Row(children: [
                              SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: cs.primary)),
                              const SizedBox(width: 12),
                              Text(c.tr('thinking'),
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant, fontSize: 13))
                            ])),
                      if (c.completion != null)
                        Container(
                            padding: const EdgeInsets.all(19),
                            decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.auto_awesome_outlined),
                                  const SizedBox(height: 10),
                                  Text(c.completion!),
                                  const SizedBox(height: 14),
                                  FilledButton(
                                      onPressed: c.chatting ? null : c.nextChat,
                                      child: Text(UiText.get(
                                          widget.controller.appLanguage,
                                          'nextConversation')))
                                ])),
                      if (c.chatError != null)
                        ErrorStrip(
                            message: c.chatError!,
                            retry: () => c.send(null, retry: true)),
                      if (c.chatError != null && c.pending != null)
                        TextButton(
                            onPressed: c.chatting ? null : c.reloadSavedChat,
                            child: Text(c.tr('reloadSavedChat')))
                    ]),
              ),
              if (audioError != null)
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 23, vertical: 7),
                    child: Text(audioError!,
                        style: TextStyle(color: cs.error, fontSize: 12))),
              if (recording)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                        UiText.get(
                            widget.controller.appLanguage, 'recordingHelp'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.secondary, fontSize: 12))),
              if (c.demo && c.completion == null && c.demoAnswer != null)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 23),
                    child: TextButton.icon(
                        onPressed: () => setState(() {
                              composer.text = c.demoAnswer!;
                            }),
                        icon: const Icon(Icons.playlist_add_rounded),
                        label: Text(c.tr('demoSampleAnswer')))),
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 9, 18, 15),
                      child: Column(children: [
                        Container(
                            padding: const EdgeInsets.fromLTRB(6, 5, 7, 5),
                            decoration: BoxDecoration(
                                color: cs.surfaceContainerLow,
                                border: Border.all(
                                    color: recording
                                        ? cs.secondary
                                        : cs.outlineVariant),
                                borderRadius: BorderRadius.circular(19)),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  IconButton(
                                      onPressed: audioBusy ||
                                              preparingMic ||
                                              c.chatting ||
                                              c.pending != null ||
                                              c.completion != null
                                          ? null
                                          : record,
                                      tooltip: recording
                                          ? UiText.get(
                                              widget.controller.appLanguage,
                                              'stopRecording')
                                          : UiText.get(
                                              widget.controller.appLanguage,
                                              'recordMessage'),
                                      icon: Icon(
                                          recording
                                              ? Icons.stop_circle_rounded
                                              : Icons.mic_none_rounded,
                                          color:
                                              recording ? cs.secondary : null)),
                                  Expanded(
                                      child: TextField(
                                          controller: composer,
                                          minLines: 1,
                                          maxLines: 4,
                                          maxLength: 1200,
                                          enabled: !recording &&
                                              !c.chatting &&
                                              c.pending == null &&
                                              c.completion == null,
                                          textInputAction: TextInputAction.send,
                                          onSubmitted: (_) => send(),
                                          onChanged: (_) => setState(() {}),
                                          decoration: InputDecoration(
                                              hintText: c.tr('composer'),
                                              border: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              filled: false,
                                              counterText: '',
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 13,
                                                      horizontal: 6)))),
                                  IconButton.filled(
                                      onPressed: composer.text.trim().isEmpty ||
                                              c.chatting ||
                                              c.pending != null ||
                                              recording ||
                                              c.completion != null
                                          ? null
                                          : send,
                                      tooltip: c.tr('send'),
                                      icon: const Icon(
                                          Icons.arrow_upward_rounded,
                                          size: 21))
                                ])),
                        const SizedBox(height: 8),
                        Text(
                            UiText.get(widget.controller.appLanguage,
                                'transcriptionNote'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant))
                      ]))),
            ])));
  }
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onSpeak;
  const MessageBubble({super.key, required this.message, this.onSpeak});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.only(bottom: 23),
        child: Align(
            alignment:
                message.user ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 610),
                child: Column(
                    crossAxisAlignment: message.user
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!message.user)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('LINGUA',
                                style: TextStyle(
                                    fontSize: 9,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary))),
                      Container(
                          padding: message.user
                              ? const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14)
                              : const EdgeInsets.only(right: 10),
                          decoration: message.user
                              ? BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(17))
                              : null,
                          child: SelectableText(message.text,
                              style: Theme.of(context).textTheme.bodyLarge)),
                      if (!message.user)
                        Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: onSpeak,
                                tooltip: UiText.of(context, 'readReply'),
                                icon: Icon(Icons.volume_up_outlined,
                                    size: 18, color: cs.onSurfaceVariant))),
                    ]))));
  }
}

Uint8List pcmToWav(Uint8List pcm, {int sampleRate = 16000}) {
  final data = ByteData(44 + pcm.length);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + pcm.length, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, pcm.length, Endian.little);
  final bytes = data.buffer.asUint8List();
  bytes.setRange(44, bytes.length, pcm);
  return bytes;
}

/// PCM stream recordings are mono 16-bit samples. Browser audio hardware often
/// uses 44.1/48 kHz even when a lower rate was requested.
int pcmSampleRate(Uint8List pcm, Duration elapsed) {
  if (pcm.length < 2 || elapsed.inMilliseconds < 100) return 16000;
  final measured = (pcm.length ~/ 2) * 1000 / elapsed.inMilliseconds;
  const supported = [8000, 12000, 16000, 22050, 24000, 32000, 44100, 48000];
  return supported.reduce((best, rate) =>
      (rate - measured).abs() < (best - measured).abs() ? rate : best);
}
