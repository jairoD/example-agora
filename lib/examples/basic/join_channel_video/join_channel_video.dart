import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_rtc_engine_example/components/example_actions_widget.dart';
import 'package:agora_rtc_engine_example/components/log_sink.dart';
import 'package:agora_rtc_engine_example/components/stats_monitoring_widget.dart';
import 'package:agora_rtc_engine_example/config/agora.config.dart' as config;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// MultiChannel Example
class JoinChannelVideo extends StatefulWidget {
  /// Construct the [JoinChannelVideo]
  const JoinChannelVideo({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _State();
}

class _State extends State<JoinChannelVideo> {
  late final RtcEngine _engine;
  int streamId = -1;
  final Map<int, String> userNicknames = {};
  bool isJoined = false,
      switchCamera = true,
      switchRender = true,
      openCamera = true,
      muteCamera = false,
      muteAllRemoteVideo = false;
  Set<int> remoteUid = {};
  late TextEditingController _controller;
  final _nameController = TextEditingController();
  bool _isUseFlutterTexture = false;
  bool _isUseAndroidSurfaceView = false;
  ChannelProfileType _channelProfileType =
      ChannelProfileType.channelProfileLiveBroadcasting;
  late final RtcEngineEventHandler _rtcEngineEventHandler;

  Timer? timeoutTimer;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: config.channelId);

    _initEngine();
  }

  @override
  void dispose() {
    super.dispose();
    _dispose();
  }

  void startTimeout() {
    cancelTimeout(); // Cancel existing timer if any
    timeoutTimer = Timer(const Duration(seconds: 10), () {
      _leaveChannel();
    });
  }

  void cancelTimeout() {
    if (timeoutTimer != null) {
      timeoutTimer!.cancel();
      timeoutTimer = null;
    }
  }

  Future<void> _showMyDialog(int uid, int streamId, String data) async {
    return showDialog(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('New user joined'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[Text('User:$data')],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Ok'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void setNickname(int uid, String nickname) {
    setState(() {
      userNicknames[uid] = nickname;
    });
  }

  Future<void> sendNickname(String nickname) async {
    try {
      final streamId = await _engine.createDataStream(
          const DataStreamConfig(syncWithAudio: false, ordered: false));
      final data = Uint8List.fromList(utf8.encode(_nameController.text));
      await _engine.sendStreamMessage(
          streamId: streamId, data: data, length: data.length);
    } catch (e) {
      print('sendStreamMessage error: ${e.toString()}');
      logSink.log('sendStreamMessage error: ${e.toString()}');
    }
  }

  Future<void> _dispose() async {
    _engine.unregisterEventHandler(_rtcEngineEventHandler);
    await _engine.leaveChannel();
    await _engine.release();
  }

  Future<void> _initEngine() async {
    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(
      appId: config.appId,
    ));
    _rtcEngineEventHandler = RtcEngineEventHandler(
      onError: (ErrorCodeType err, String msg) {
        logSink.log('[onError] err: $err, msg: $msg');
      },
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        print('I Joined the channel');
        ;
        logSink.log(
            '[onJoinChannelSuccess] connection: ${connection.toJson()} elapsed: $elapsed');
        startTimeout();
        setState(() {
          isJoined = true;
        });
      },
      onUserJoined: (RtcConnection connection, int rUid, int elapsed) {
        logSink.log(
            '[onUserJoined] connection: ${connection.toJson()} remoteUid: $rUid elapsed: $elapsed');
        setState(() {
          cancelTimeout();
          remoteUid.add(rUid);
        });
      },
      onStreamMessage: (connection, remoteUid, streamId, data, length, sentTs) {
        print('onStreamMessage');
        setNickname(remoteUid, utf8.decode(data));
        _showMyDialog(remoteUid, streamId, utf8.decode(data));
      },
      onUserOffline:
          (RtcConnection connection, int rUid, UserOfflineReasonType reason) {
        logSink.log(
            '[onUserOffline] connection: ${connection.toJson()}  rUid: $rUid reason: $reason');
        setState(() {
          remoteUid.removeWhere((element) => element == rUid);
          if (remoteUid.isEmpty) {
            startTimeout();
          }
        });
      },
      onLeaveChannel: (RtcConnection connection, RtcStats stats) {
        logSink.log(
            '[onLeaveChannel] connection: ${connection.toJson()} stats: ${stats.toJson()}');
        setState(() {
          isJoined = false;
          remoteUid.clear();
        });
      },
      onRemoteVideoStateChanged: (RtcConnection connection, int remoteUid,
          RemoteVideoState state, RemoteVideoStateReason reason, int elapsed) {
        logSink.log(
            '[onRemoteVideoStateChanged] connection: ${connection.toJson()} remoteUid: $remoteUid state: $state reason: $reason elapsed: $elapsed');
      },
    );

    _engine.registerEventHandler(_rtcEngineEventHandler);

    await _engine.enableVideo();
    await _engine.startPreview();
  }

  Future<void> _joinChannel() async {
    try {
      await _engine.joinChannel(
        token: config.token,
        channelId: _controller.text,
        uid: config.uid,
        options: ChannelMediaOptions(
          channelProfile: _channelProfileType,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      await sendNickname(_nameController.text);
      setState(() {
        userNicknames[config.uid] = _nameController.text;
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> _leaveChannel() async {
    await _engine.leaveChannel();
    setState(() {
      openCamera = true;
      muteCamera = false;
      muteAllRemoteVideo = false;
    });
  }

  Future<void> _switchCamera() async {
    await _engine.switchCamera();
    setState(() {
      switchCamera = !switchCamera;
    });
  }

  _openCamera() async {
    await _engine.enableLocalVideo(!openCamera);
    setState(() {
      openCamera = !openCamera;
    });
  }

  _muteLocalVideoStream() async {
    await _engine.muteLocalVideoStream(!muteCamera);
    setState(() {
      muteCamera = !muteCamera;
    });
  }

  _muteAllRemoteVideoStreams() async {
    await _engine.muteAllRemoteVideoStreams(!muteAllRemoteVideo);
    setState(() {
      muteAllRemoteVideo = !muteAllRemoteVideo;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExampleActionsWidget(
      displayContentBuilder: (context, isLayoutHorizontal) {
        return Stack(
          children: [
            StatsMonitoringWidget(
              rtcEngine: _engine,
              uid: 0,
              child: AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: _engine,
                  canvas: const VideoCanvas(uid: 0),
                  useFlutterTexture: _isUseFlutterTexture,
                  useAndroidSurfaceView: _isUseAndroidSurfaceView,
                ),
                onAgoraVideoViewCreated: (viewId) {
                  _engine.startPreview();
                },
              ),
            ),
            if (remoteUid.isEmpty)
              const Align(
                alignment: Alignment.center,
                child: Text(
                  'Waiting for users to join...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.of(remoteUid.map(
                    (e) => SizedBox(
                      width: 200,
                      height: 200,
                      child: StatsMonitoringWidget(
                        rtcEngine: _engine,
                        uid: e,
                        channelId: _controller.text,
                        child: AgoraVideoView(
                          controller: VideoViewController.remote(
                            rtcEngine: _engine,
                            canvas: VideoCanvas(uid: e),
                            connection:
                                RtcConnection(channelId: _controller.text),
                            useFlutterTexture: _isUseFlutterTexture,
                            useAndroidSurfaceView: _isUseAndroidSurfaceView,
                          ),
                        ),
                      ),
                    ),
                  )),
                ),
              ),
            )
          ],
        );
      },
      actionsBuilder: (context, isLayoutHorizontal) {
        final channelProfileType = [
          ChannelProfileType.channelProfileLiveBroadcasting,
          ChannelProfileType.channelProfileCommunication,
        ];
        final items = channelProfileType
            .map((e) => DropdownMenuItem(
                  child: Text(
                    e.toString().split('.')[1],
                  ),
                  value: e,
                ))
            .toList();

        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: 'NickName'),
            ),
            TextField(
              enabled: false,
              controller: _controller,
              decoration: const InputDecoration(hintText: 'Channel ID'),
            ),
            /* if (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS))
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Rendered by Flutter texture: '),
                        Switch(
                          value: _isUseFlutterTexture,
                          onChanged: isJoined
                              ? null
                              : (changed) {
                                  setState(() {
                                    _isUseFlutterTexture = changed;
                                  });
                                },
                        )
                      ]),
                ],
              ),
            const SizedBox(
              height: 20,
            ),
            const Text('Channel Profile: '),
            DropdownButton<ChannelProfileType>(
              items: items,
              value: _channelProfileType,
              onChanged: isJoined
                  ? null
                  : (v) {
                      setState(() {
                        _channelProfileType = v!;
                      });
                    },
            ),
            const SizedBox(
              height: 20,
            ),
            BasicVideoConfigurationWidget(
              rtcEngine: _engine,
              title: 'Video Encoder Configuration',
              setConfigButtonText: const Text(
                'setVideoEncoderConfiguration',
                style: TextStyle(fontSize: 10),
              ),
              onConfigChanged: (width, height, frameRate, bitrate) {
                _engine.setVideoEncoderConfiguration(VideoEncoderConfiguration(
                  dimensions: VideoDimensions(width: width, height: height),
                  frameRate: frameRate,
                  bitrate: bitrate,
                ));
              },
            ), */
            const SizedBox(
              height: 20,
            ),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    onPressed: isJoined ? _leaveChannel : _joinChannel,
                    child: Text('${isJoined ? 'Leave' : 'Join'} channel'),
                  ),
                )
              ],
            ),
            if (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS)) ...[
              const SizedBox(
                height: 20,
              ),
              ElevatedButton(
                onPressed: _switchCamera,
                child: Text('Camera ${switchCamera ? 'front' : 'rear'}'),
              ),
            ],
            if (kIsWeb) ...[
              const SizedBox(
                height: 20,
              ),
              ElevatedButton(
                onPressed: _muteLocalVideoStream,
                child: Text('Camera ${muteCamera ? 'muted' : 'unmute'}'),
              ),
              ElevatedButton(
                onPressed: _muteAllRemoteVideoStreams,
                child: Text(
                    'All Remote Camera ${muteAllRemoteVideo ? 'muted' : 'unmute'}'),
              ),
              ElevatedButton(
                onPressed: _openCamera,
                child: Text('Camera ${openCamera ? 'on' : 'off'}'),
              ),
            ],
          ],
        );
      },
    );
    // if (!_isInit) return Container();
  }
}
