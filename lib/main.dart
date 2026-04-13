import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VanSoleApp());
}

// The live game is composed inside a fixed 320x200 cockpit frame and then
// scaled up, which keeps the UI layout stable across desktop and mobile sizes.
const String _releaseVersion = '0.1.1';

const Rect _dosViewportRect = Rect.fromLTWH(0, 0, 224, 190);
const Rect _dosViewportInnerRect = Rect.fromLTWH(2, 2, 220, 186);
const Rect _dosPanelRect = Rect.fromLTWH(225, 0, 95, 200);

/// Root application shell for the public cross-platform build.
class VanSoleApp extends StatelessWidget {
  const VanSoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF1DD3B0),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF34E7C5),
          secondary: const Color(0xFFFFB454),
          surface: const Color(0xFF101823),
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Van Solè',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.black,
        tooltipTheme: TooltipThemeData(
          waitDuration: const Duration(milliseconds: 250),
          showDuration: const Duration(seconds: 4),
          preferBelow: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1520).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF34E7C5).withValues(alpha: 0.3),
            ),
          ),
          textStyle: const TextStyle(
            color: Color(0xFFF2F7FB),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(height: 1.2),
        ),
      ),
      home: const VanSoleHomePage(),
    );
  }
}

class VanSoleHomePage extends StatefulWidget {
  const VanSoleHomePage({super.key});

  @override
  State<VanSoleHomePage> createState() => _VanSoleHomePageState();
}

// Owns the simulation loop, input mapping, save/load controls, and the
// responsive shell that wraps the fixed cockpit renderer.
class _VanSoleHomePageState extends State<VanSoleHomePage>
    with SingleTickerProviderStateMixin {
  late VanSoleGame _game;
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode(debugLabel: 'sector-view');
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  final Set<VirtualAction> _touchActions = <VirtualAction>{};
  final TextEditingController _saveCodeController = TextEditingController();
  Duration? _lastTick;
  int _lastAudioCueSerial = 0;
  String _saveStatus = 'No save exported yet.';
  String? _quickSaveCode;
  SessionMode _sessionMode = SessionMode.title;

  @override
  void initState() {
    super.initState();
    _game = VanSoleGame();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    _saveCodeController.dispose();
    super.dispose();
  }

  void _onTick(Duration timestamp) {
    final last = _lastTick;
    _lastTick = timestamp;
    if (last == null || !mounted) {
      return;
    }
    final dt = ((timestamp - last).inMicroseconds / 1000000.0)
        .clamp(0.0, 0.05)
        .toDouble();
    if (dt <= 0) {
      return;
    }
    setState(() {
      if (_sessionMode == SessionMode.playing) {
        _game.update(dt, _currentInput());
      }
      _drainAudioCue();
    });
  }

  void _drainAudioCue() {
    if (_game.audioCueSerial == _lastAudioCueSerial) {
      return;
    }
    _lastAudioCueSerial = _game.audioCueSerial;
    final cue = _game.lastAudioCue;
    if (cue == null) {
      return;
    }
    switch (cue) {
      case GameAudioCue.fire:
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.lightImpact();
        break;
      case GameAudioCue.contract:
      case GameAudioCue.comms:
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.selectionClick();
        break;
      case GameAudioCue.hit:
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.mediumImpact();
        break;
      case GameAudioCue.warning:
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.selectionClick();
        break;
      case GameAudioCue.dock:
      case GameAudioCue.jump:
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.mediumImpact();
        break;
    }
  }

  void _mutateGame(VoidCallback mutate) {
    setState(() {
      mutate();
      _drainAudioCue();
    });
  }

  void _startNewCampaign() {
    setState(() {
      _game = VanSoleGame();
      _lastAudioCueSerial = 0;
      _sessionMode = SessionMode.playing;
      _pressedKeys.clear();
      _touchActions.clear();
      _saveStatus = 'New campaign started.';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _resumePlay() {
    setState(() {
      _sessionMode = SessionMode.playing;
      _pressedKeys.clear();
      _touchActions.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _pausePlay() {
    setState(() {
      _sessionMode = SessionMode.paused;
      _pressedKeys.clear();
      _touchActions.clear();
    });
  }

  void _returnToTitle() {
    setState(() {
      _sessionMode = SessionMode.title;
      _pressedKeys.clear();
      _touchActions.clear();
    });
  }

  Future<void> _copySaveCode() async {
    final code = _game.exportSaveCode();
    _saveCodeController.text = code;
    _quickSaveCode = code;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) {
      return;
    }
    setState(() {
      _saveStatus =
          'Save code copied (${code.length} chars). Quick slot updated.';
    });
  }

  Future<void> _pasteSaveCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) {
      return;
    }
    setState(() {
      _saveCodeController.text = data?.text ?? '';
      _saveStatus = _saveCodeController.text.isEmpty
          ? 'Clipboard was empty.'
          : 'Pasted save code from clipboard.';
    });
  }

  void _loadFromSaveField() {
    final raw = _saveCodeController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _saveStatus = 'Paste or export a save code first.';
      });
      return;
    }
    try {
      _mutateGame(() => _game.importSaveCode(raw));
      setState(() {
        _saveStatus = 'Save loaded successfully.';
      });
    } catch (error) {
      setState(() {
        _saveStatus = 'Load failed: $error';
      });
    }
  }

  void _quickSave() {
    final code = _game.exportSaveCode();
    _quickSaveCode = code;
    setState(() {
      _saveStatus = 'Quick save slot updated.';
      _saveCodeController.text = code;
    });
  }

  void _quickLoad() {
    final code = _quickSaveCode;
    if (code == null) {
      setState(() {
        _saveStatus = 'Quick save slot is empty.';
      });
      return;
    }
    try {
      _mutateGame(() => _game.importSaveCode(code));
      setState(() {
        _saveStatus = 'Quick save loaded.';
        _saveCodeController.text = code;
        _sessionMode = SessionMode.playing;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    } catch (error) {
      setState(() {
        _saveStatus = 'Quick load failed: $error';
      });
    }
  }

  PlayerInput _currentInput() {
    if (_sessionMode != SessionMode.playing) {
      return const PlayerInput(
        up: false,
        down: false,
        left: false,
        right: false,
        fire: false,
        boost: false,
      );
    }
    bool hasAny(Set<LogicalKeyboardKey> keys) =>
        keys.any((key) => _pressedKeys.contains(key));

    return PlayerInput(
      up:
          hasAny({LogicalKeyboardKey.keyW, LogicalKeyboardKey.arrowUp}) ||
          _touchActions.contains(VirtualAction.up),
      down:
          hasAny({LogicalKeyboardKey.keyS, LogicalKeyboardKey.arrowDown}) ||
          _touchActions.contains(VirtualAction.down),
      left:
          hasAny({LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowLeft}) ||
          _touchActions.contains(VirtualAction.left),
      right:
          hasAny({LogicalKeyboardKey.keyD, LogicalKeyboardKey.arrowRight}) ||
          _touchActions.contains(VirtualAction.right),
      fire:
          _pressedKeys.contains(LogicalKeyboardKey.space) ||
          _touchActions.contains(VirtualAction.fire),
      boost:
          _pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
          _pressedKeys.contains(LogicalKeyboardKey.shiftRight) ||
          _touchActions.contains(VirtualAction.boost),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _pressedKeys.add(key);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
    }

    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.escape) {
        if (_sessionMode == SessionMode.playing) {
          _pausePlay();
        } else if (_sessionMode == SessionMode.paused) {
          _resumePlay();
        }
        return KeyEventResult.handled;
      }
      if (_sessionMode == SessionMode.title) {
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space) {
          _startNewCampaign();
        } else if (key == LogicalKeyboardKey.keyL) {
          _quickLoad();
        }
        return KeyEventResult.handled;
      }
      if (_sessionMode == SessionMode.paused) {
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space) {
          _resumePlay();
        } else if (key == LogicalKeyboardKey.keyQ) {
          _returnToTitle();
        } else if (key == LogicalKeyboardKey.keyK) {
          _quickSave();
        } else if (key == LogicalKeyboardKey.keyL) {
          _quickLoad();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyE) {
        _mutateGame(_game.toggleDocking);
      } else if (key == LogicalKeyboardKey.keyF) {
        _mutateGame(_game.tryAcceptDockContract);
      } else if (key == LogicalKeyboardKey.keyR) {
        _mutateGame(_game.tryDeliverDockContract);
      } else if (key == LogicalKeyboardKey.keyJ) {
        _mutateGame(_game.attemptJump);
      } else if (key == LogicalKeyboardKey.keyT) {
        _mutateGame(_game.cycleTracking);
      } else if (key == LogicalKeyboardKey.keyC) {
        _mutateGame(_game.requestComms);
      } else if (key == LogicalKeyboardKey.keyH) {
        _mutateGame(_game.harvestResource);
      } else if (key == LogicalKeyboardKey.digit1) {
        _mutateGame(() {
          if (_game.activeEncounter != null) {
            _game.chooseDialogueOption(0);
          } else {
            _game.setCockpitMode(1);
          }
        });
      } else if (key == LogicalKeyboardKey.digit2) {
        _mutateGame(() {
          if (_game.activeEncounter != null) {
            _game.chooseDialogueOption(1);
          } else {
            _game.setCockpitMode(2);
          }
        });
      } else if (key == LogicalKeyboardKey.digit3) {
        _mutateGame(() {
          if (_game.activeEncounter != null) {
            _game.chooseDialogueOption(2);
          } else {
            _game.setCockpitMode(3);
          }
        });
      } else if (key == LogicalKeyboardKey.digit4) {
        _mutateGame(() => _game.setCockpitMode(4));
      } else if (key == LogicalKeyboardKey.digit5) {
        _mutateGame(() => _game.setCockpitMode(5));
      } else if (key == LogicalKeyboardKey.digit6) {
        _mutateGame(() => _game.setCockpitMode(6));
      }
    }

    return KeyEventResult.handled;
  }

  void _setTouchAction(VirtualAction action, bool active) {
    setState(() {
      if (active) {
        _touchActions.add(action);
      } else {
        _touchActions.remove(action);
      }
    });
  }

  String _objectiveLabel() {
    final mission = _game.activeCampaignMission;
    if (mission == null) {
      return 'Campaign complete. Free-roam contracts and combat are active.';
    }
    return 'Objective: ${mission.title} (${_game.campaignProgressText})';
  }

  Widget _buildSessionOverlay(ColorScheme colors) {
    if (_sessionMode == SessionMode.playing) {
      return const SizedBox.shrink();
    }
    final title = _sessionMode == SessionMode.title ? 'VAN SOLÈ' : 'PAUSED';
    final subtitle = _sessionMode == SessionMode.title
        ? 'Cross-platform spacefaring action RPG'
        : 'Press Esc to resume flight controls';
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF05070D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_sessionMode == SessionMode.title)
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF10223A), Color(0xFF04080D)],
                            ),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'VAN SOLÈ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.secondary,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.4,
                                fontFamilyFallback: const [
                                  'Menlo',
                                  'Monaco',
                                  'Courier New',
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_sessionMode == SessionMode.title)
                        const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          fontFamilyFallback: [
                            'Menlo',
                            'Monaco',
                            'Courier New',
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamilyFallback: [
                            'Menlo',
                            'Monaco',
                            'Courier New',
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _objectiveLabel(),
                        style: TextStyle(
                          color: colors.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _withTooltip(
                            _sessionMode == SessionMode.title
                                ? 'Start a new campaign.'
                                : 'Return to the live flight view.',
                            FilledButton.tonal(
                              key: const Key('start-campaign-button'),
                              onPressed: _sessionMode == SessionMode.title
                                  ? _startNewCampaign
                                  : _resumePlay,
                              child: Text(
                                _sessionMode == SessionMode.title
                                    ? 'Start Campaign'
                                    : 'Resume (Esc)',
                              ),
                            ),
                          ),
                          _withTooltip(
                            'Load the current quick-save slot.',
                            OutlinedButton(
                              onPressed: _quickSaveCode == null
                                  ? null
                                  : _quickLoad,
                              child: const Text('Load Quick Save (L)'),
                            ),
                          ),
                          _withTooltip(
                            'Write the current run into the quick-save slot.',
                            OutlinedButton(
                              onPressed: _quickSave,
                              child: const Text('Quick Save (K)'),
                            ),
                          ),
                          if (_sessionMode == SessionMode.paused)
                            _withTooltip(
                              'Leave the current session and go back to the title screen.',
                              OutlinedButton(
                                onPressed: _returnToTitle,
                                child: const Text('Return to Title (Q)'),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Controls: WASD/Arrows thrust, Space fire, Shift boost, T track, C comms, H harvest, E dock, J jump, F/R contract, 1-6 panel modes.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Release v$_releaseVersion  |  Support: buymeacoffee.com/einnovoeg',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGamePane(BuildContext context, bool compact) {
    final colors = Theme.of(context).colorScheme;
    final immersivePlay = _sessionMode == SessionMode.playing;
    return Padding(
      padding: EdgeInsets.all(immersivePlay ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!immersivePlay && compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Van Solè',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Spacefaring action RPG',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        'Sector: ${_game.sectorName}',
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111D2A),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        'MODE ${_sessionMode.name.toUpperCase()}',
                        style: TextStyle(
                          color: _sessionMode == SessionMode.playing
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFE5D089),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          else if (!immersivePlay)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Van Solè',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Campaign-driven exploration, trading, combat, and ship management',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Sector: ${_game.sectorName}',
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111D2A),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    'MODE ${_sessionMode.name.toUpperCase()}',
                    style: TextStyle(
                      color: _sessionMode == SessionMode.playing
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFE5D089),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          if (!immersivePlay) const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(immersivePlay ? 0 : 20),
                border: immersivePlay
                    ? null
                    : Border.all(color: colors.primary.withValues(alpha: 0.18)),
                boxShadow: immersivePlay
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                gradient: immersivePlay
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF000000), Color(0xFF03070D)],
                      )
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0B1017), Color(0xFF08121D)],
                      ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(immersivePlay ? 0 : 20),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Focus(
                        autofocus: true,
                        focusNode: _focusNode,
                        onKeyEvent: _handleKeyEvent,
                        child: GestureDetector(
                          onTap: () => _focusNode.requestFocus(),
                          child: _CockpitSurface(
                            key: const Key('flight-surface'),
                            game: _game,
                          ),
                        ),
                      ),
                    ),
                    if (!immersivePlay)
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          runSpacing: 8,
                          spacing: 8,
                          children: [
                            _Pill(
                              label: _game.isDocked
                                  ? 'Docked at ${_game.dockedStation!.name}'
                                  : _game.dockCandidate != null
                                  ? 'Docking window open (${_game.dockCandidate!.name})'
                                  : 'In flight',
                              color: _game.isDocked
                                  ? const Color(0xFF4ADE80)
                                  : (_game.dockCandidate != null
                                        ? const Color(0xFFFBBF24)
                                        : const Color(0xFF93C5FD)),
                            ),
                            _Pill(
                              label: _objectiveLabel(),
                              color: const Color(0xFFFBBF24),
                              muted: true,
                            ),
                            _Pill(
                              label:
                                  'TRACKING [T] | COMM [C] | THRUST WASD | FIRE SPACE | BOOST SHIFT | DOCK E | JUMP J | PAUSE ESC',
                              color: const Color(0xFFCBD5E1),
                              muted: true,
                            ),
                            if (_game.jumpCandidate != null)
                              _Pill(
                                label:
                                    'Jump gate ready: ${_game.jumpCandidate!.name} (press J)',
                                color: const Color(0xFFA78BFA),
                              ),
                          ],
                        ),
                      ),
                    if (compact && _sessionMode == SessionMode.playing) ...[
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _TouchControls(
                          onDockTap: () => _mutateGame(_game.toggleDocking),
                          onJumpTap: () => _mutateGame(_game.attemptJump),
                          onAction: _setTouchAction,
                        ),
                      ),
                    ],
                    _buildSessionOverlay(colors),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHudPane(BuildContext context, bool compact) {
    final colors = Theme.of(context).colorScheme;
    final cards = <Widget>[
      _HudCard(
        title: 'CONTROL PANEL',
        trailing: Text(
          'Threat ${_game.pirates.length}',
          style: TextStyle(
            color: colors.secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Column(
          children: [
            _MeterRow(
              label: 'HULL',
              value: _game.playerHull / 100,
              text: _pct(_game.playerHull),
              color: const Color(0xFFF87171),
            ),
            _MeterRow(
              label: 'SHIELD',
              value: _game.playerShield / _game.shieldCapacity,
              text:
                  '${_game.playerShield.round()}/${_game.shieldCapacity.round()}',
              color: const Color(0xFF60A5FA),
            ),
            _MeterRow(
              label: 'ENERGY',
              value: _game.playerEnergy / 100,
              text: _pct(_game.playerEnergy),
              color: const Color(0xFF34D399),
            ),
            _MeterRow(
              label: 'FUEL',
              value: _game.playerFuel / 100,
              text: _pct(_game.playerFuel),
              color: const Color(0xFFFBBF24),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TagMetric(label: 'CREDITS', value: '${_game.credits} cr'),
                _TagMetric(
                  label: 'CARGO',
                  value:
                      '${_game.totalCargoUsed}/${_game.cargoCapacity} (${_game.tradeCargoUsed} trade)',
                ),
                _TagMetric(
                  label: 'NEAREST',
                  value: _game.nearestStation == null
                      ? '-'
                      : '${_game.nearestStation!.name} ${_distanceKm(_game.nearestStationDistance)}',
                ),
                _TagMetric(
                  label: 'PIRATE',
                  value: _game.nearestPirateDistance.isFinite
                      ? _distanceKm(_game.nearestPirateDistance)
                      : 'clear',
                ),
                _TagMetric(
                  label: 'GATE',
                  value: _game.nearestPortalDistance.isFinite
                      ? _distanceKm(_game.nearestPortalDistance)
                      : 'none',
                ),
              ],
            ),
          ],
        ),
      ),
      _HudCard(
        title: 'RADAR / SPEED',
        trailing: Text(
          _distanceKm(VanSoleGame.radarRange),
          style: TextStyle(color: colors.primary),
        ),
        child: Center(
          child: SizedBox(
            width: compact ? 220 : 260,
            height: compact ? 220 : 260,
            child: CustomPaint(painter: RadarPainter(_game)),
          ),
        ),
      ),
      _HudCard(
        title: 'Field Notes',
        trailing: Text(
          '${_game.unlockedLoreEntries.length} logs',
          style: TextStyle(color: colors.secondary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _game.harvestCandidate != null
                  ? 'Harvest window open: ${_game.harvestCandidate!.name}'
                  : _game.nearestResource != null
                  ? 'Nearest field: ${_game.nearestResource!.name} ${_distanceKm(_game.nearestResourceDistance)}'
                  : 'No active field contacts in local range.',
              style: TextStyle(
                color: _game.harvestCandidate != null
                    ? const Color(0xFF4ADE80)
                    : colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _game.nearestResource?.scanSummary ??
                  'Science scans and harvest passes unlock permanent field notes and resource lore.',
              style: const TextStyle(color: Colors.white70),
            ),
            if (_game.latestLoreEntry != null) ...[
              const SizedBox(height: 10),
              Text(
                _game.latestLoreEntry!.title,
                style: TextStyle(
                  color: colors.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _game.latestLoreEntry!.body,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      _HudCard(
        title: 'Galaxy Map',
        trailing: Text(
          _game.sectorName,
          style: TextStyle(color: colors.secondary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 160,
              child: CustomPaint(painter: GalaxyMapPainter(_game)),
            ),
            const SizedBox(height: 8),
            Text(
              _game.jumpCandidate == null
                  ? 'Approach a jump gate and slow down to transit sectors.'
                  : 'Jump gate ${_game.jumpCandidate!.name} ready (press J).',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
      _HudCard(
        title: 'Campaign',
        trailing: Text(
          _game.campaignStatusLabel,
          style: TextStyle(
            color: _game.campaignComplete
                ? const Color(0xFF4ADE80)
                : colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _game.campaignTitle,
              style: TextStyle(
                color: _game.campaignComplete
                    ? const Color(0xFF4ADE80)
                    : colors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _game.campaignDescription,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Container(
                height: 10,
                color: const Color(0xFF0C121B),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _game.campaignProgressFraction,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colors.primary.withValues(alpha: 0.6),
                          colors.primary,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Progress: ${_game.campaignProgressText}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                if (!_game.campaignComplete)
                  Text(
                    'Reward: ${_game.campaignRewardCredits} cr',
                    style: TextStyle(
                      color: colors.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      _HudCard(
        title: 'AVAILABLE POWER',
        trailing: Text(
          '${_game.totalPowerAllocation}%',
          style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700),
        ),
        child: Column(
          children: PowerChannel.values
              .map(
                (channel) => _PowerRow(
                  channel: channel,
                  value: _game.power[channel]!,
                  onAdjust: (delta) =>
                      _mutateGame(() => _game.adjustPower(channel, delta)),
                ),
              )
              .toList(),
        ),
      ),
      _HudCard(
        title: 'Outfitting',
        trailing: Text(
          _game.isDocked ? 'Docked' : 'Dock to upgrade',
          style: TextStyle(
            color: _game.isDocked ? colors.primary : Colors.white60,
            fontSize: 12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UpgradeRow(
              label: 'Engines',
              tier: _game.engineUpgradeTier,
              maxTier: _game.maxEngineUpgradeTier,
              cost: _game.engineUpgradeCost,
              onPressed: _game.canUpgradeEngine
                  ? () => _mutateGame(_game.buyEngineUpgrade)
                  : null,
            ),
            _UpgradeRow(
              label: 'Weapons',
              tier: _game.weaponUpgradeTier,
              maxTier: _game.maxWeaponUpgradeTier,
              cost: _game.weaponUpgradeCost,
              onPressed: _game.canUpgradeWeapons
                  ? () => _mutateGame(_game.buyWeaponUpgrade)
                  : null,
            ),
            _UpgradeRow(
              label: 'Shields',
              tier: _game.shieldUpgradeTier,
              maxTier: _game.maxShieldUpgradeTier,
              cost: _game.shieldUpgradeCost,
              onPressed: _game.canUpgradeShields
                  ? () => _mutateGame(_game.buyShieldUpgrade)
                  : null,
            ),
            _UpgradeRow(
              label: 'Cargo',
              tier: _game.cargoUpgradeTier,
              maxTier: _game.maxCargoUpgradeTier,
              cost: _game.cargoUpgradeCost,
              onPressed: _game.canUpgradeCargo
                  ? () => _mutateGame(_game.buyCargoUpgrade)
                  : null,
              valueText: '${_game.cargoCapacity} units',
            ),
          ],
        ),
      ),
      if (_game.activeEncounter != null)
        _HudCard(
          title: 'Live Comms',
          trailing: Text(
            '1-${_game.activeEncounter!.options.length}',
            style: TextStyle(color: colors.primary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _game.activeEncounter!.title,
                style: TextStyle(
                  color: colors.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _game.activeEncounter!.body,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < _game.activeEncounter!.options.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == _game.activeEncounter!.options.length - 1
                        ? 0
                        : 8,
                  ),
                  child: _withTooltip(
                    'Send response ${i + 1} to the open comms channel.',
                    FilledButton.tonal(
                      onPressed: () =>
                          _mutateGame(() => _game.chooseDialogueOption(i)),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${i + 1}. ${_game.activeEncounter!.options[i].label}',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      _HudCard(
        title: 'Contracts',
        trailing: Text(
          _game.contractStateLabel,
          style: TextStyle(
            color: _game.activeContract == null
                ? Colors.white70
                : const Color(0xFF4ADE80),
            fontWeight: FontWeight.w700,
          ),
        ),
        child: _MissionPanel(game: _game),
      ),
      if (_game.isDocked)
        _HudCard(
          title: 'Dock Services',
          trailing: Text(
            _game.dockedStation!.name,
            style: TextStyle(color: colors.secondary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _game.currentDockDescription,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                'Reputation: ${_game.currentDockReputationLabel}',
                style: TextStyle(
                  color: _game.currentDockContractsLocked
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFF93C5FD),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _withTooltip(
                    'Accept the current station contract.',
                    FilledButton.tonal(
                      onPressed: _game.canAcceptDockContract
                          ? () => _mutateGame(_game.tryAcceptDockContract)
                          : null,
                      child: const Text('Accept (F)'),
                    ),
                  ),
                  _withTooltip(
                    'Deliver the active contract cargo.',
                    FilledButton.tonal(
                      onPressed: _game.canDeliverDockContract
                          ? () => _mutateGame(_game.tryDeliverDockContract)
                          : null,
                      child: const Text('Deliver (R)'),
                    ),
                  ),
                  _withTooltip(
                    'Repair ship hull damage for 40 credits.',
                    FilledButton.tonal(
                      onPressed: _game.canRepairHull
                          ? () => _mutateGame(_game.repairHull)
                          : null,
                      child: const Text('Repair 40 cr'),
                    ),
                  ),
                  _withTooltip(
                    'Refill fuel reserves for 20 credits.',
                    FilledButton.tonal(
                      onPressed: _game.canRefuel
                          ? () => _mutateGame(_game.refuel)
                          : null,
                      child: const Text('Refuel 20 cr'),
                    ),
                  ),
                  _withTooltip(
                    'Leave the station and return to open flight.',
                    OutlinedButton(
                      onPressed: () => _mutateGame(_game.toggleDocking),
                      child: const Text('Undock (E)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _MarketPanel(
                game: _game,
                onBuy: (commodityId) =>
                    _mutateGame(() => _game.buyCommodity(commodityId)),
                onSell: (commodityId) =>
                    _mutateGame(() => _game.sellCommodity(commodityId)),
              ),
            ],
          ),
        ),
      _HudCard(
        title: 'Save / Load',
        trailing: Text(
          _quickSaveCode == null ? 'No quick slot' : 'Quick slot ready',
          style: TextStyle(
            color: _quickSaveCode == null ? Colors.white60 : colors.primary,
            fontSize: 12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _saveStatus,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _withTooltip(
              'Paste a save code here to import a run, or inspect the exported quick-save payload.',
              TextField(
                controller: _saveCodeController,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamilyFallback: ['Menlo', 'Monaco', 'Courier New'],
                ),
                decoration: InputDecoration(
                  hintText: 'Save code (JSON)',
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF0F1721),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _withTooltip(
                  'Export the current run and copy the save code to the clipboard.',
                  FilledButton.tonal(
                    onPressed: () => _copySaveCode(),
                    child: const Text('Copy Save'),
                  ),
                ),
                _withTooltip(
                  'Paste a save code from the clipboard into the field.',
                  FilledButton.tonal(
                    onPressed: () => _pasteSaveCode(),
                    child: const Text('Paste'),
                  ),
                ),
                _withTooltip(
                  'Import the save code currently in the field.',
                  FilledButton.tonal(
                    onPressed: _loadFromSaveField,
                    child: const Text('Load'),
                  ),
                ),
                _withTooltip(
                  'Update the in-memory quick-save slot.',
                  OutlinedButton(
                    onPressed: _quickSave,
                    child: const Text('Quick Save'),
                  ),
                ),
                _withTooltip(
                  'Restore the current quick-save slot.',
                  OutlinedButton(
                    onPressed: _quickLoad,
                    child: const Text('Quick Load'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      _HudCard(
        title: 'Comms Log',
        trailing: Text(
          '${_game.kills} kills',
          style: TextStyle(
            color: colors.secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _game.commsLog
                .map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Color(0xFFD6E4F0),
                        fontFamilyFallback: ['Menlo', 'Monaco', 'Courier New'],
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 0, 12, 12, 12),
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              cards[i],
              if (i != cards.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF05070B), Color(0xFF08131F), Color(0xFF05080E)],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1100;
              if (_sessionMode == SessionMode.playing) {
                return _buildGamePane(context, compact);
              }
              if (compact) {
                return Column(
                  children: [
                    Expanded(flex: 5, child: _buildGamePane(context, true)),
                    Expanded(flex: 4, child: _buildHudPane(context, true)),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 7, child: _buildGamePane(context, false)),
                  SizedBox(width: 420, child: _buildHudPane(context, false)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// The viewport stays intentionally thin: the scene is rendered by the
// painter into the 320x200 cockpit space and then scaled as a single unit.
class _CockpitSurface extends StatelessWidget {
  const _CockpitSurface({super.key, required this.game});

  final VanSoleGame game;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cockpit view of space',
      child: ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: CustomPaint(painter: Sector3DPainter(game, drawLegacyHud: false)),
        ),
      ),
    );
  }
}

String _pct(double value) => '${value.clamp(0, 100).round()}%';

String _distanceKm(double worldUnits) {
  final km = worldUnits / 100.0;
  if (km >= 10) {
    return '${km.round()} km';
  }
  return '${km.toStringAsFixed(1)} km';
}

Widget _withTooltip(String message, Widget child) {
  return Tooltip(message: message, child: child);
}

enum SessionMode { title, playing, paused }

enum VirtualAction { up, down, left, right, fire, boost }

class _TouchControls extends StatelessWidget {
  const _TouchControls({
    required this.onAction,
    required this.onDockTap,
    required this.onJumpTap,
  });

  final void Function(VirtualAction action, bool active) onAction;
  final VoidCallback onDockTap;
  final VoidCallback onJumpTap;

  Widget _holdButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onDown,
    required VoidCallback onUp,
    Color? color,
  }) {
    return _withTooltip(
      tooltip,
      Listener(
        onPointerDown: (_) => onDown(),
        onPointerUp: (_) => onUp(),
        onPointerCancel: (_) => onUp(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (color ?? const Color(0xFF101B28)).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: SizedBox(
            width: 60,
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _holdButton(
              icon: Icons.keyboard_arrow_up_rounded,
              label: 'Up',
              tooltip: 'Apply forward thrust.',
              onDown: () => onAction(VirtualAction.up, true),
              onUp: () => onAction(VirtualAction.up, false),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _holdButton(
                  icon: Icons.keyboard_arrow_left_rounded,
                  label: 'Left',
                  tooltip: 'Yaw the ship to port.',
                  onDown: () => onAction(VirtualAction.left, true),
                  onUp: () => onAction(VirtualAction.left, false),
                ),
                const SizedBox(width: 8),
                _holdButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  label: 'Down',
                  tooltip: 'Apply reverse thrust.',
                  onDown: () => onAction(VirtualAction.down, true),
                  onUp: () => onAction(VirtualAction.down, false),
                ),
                const SizedBox(width: 8),
                _holdButton(
                  icon: Icons.keyboard_arrow_right_rounded,
                  label: 'Right',
                  tooltip: 'Yaw the ship to starboard.',
                  onDown: () => onAction(VirtualAction.right, true),
                  onUp: () => onAction(VirtualAction.right, false),
                ),
              ],
            ),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _holdButton(
                  icon: Icons.bolt_rounded,
                  label: 'Boost',
                  tooltip: 'Spend energy for a forward speed boost.',
                  color: const Color(0xFF3F2A11),
                  onDown: () => onAction(VirtualAction.boost, true),
                  onUp: () => onAction(VirtualAction.boost, false),
                ),
                const SizedBox(width: 8),
                _holdButton(
                  icon: Icons.flash_on_rounded,
                  label: 'Fire',
                  tooltip: 'Fire the primary weapons.',
                  color: const Color(0xFF30111A),
                  onDown: () => onAction(VirtualAction.fire, true),
                  onUp: () => onAction(VirtualAction.fire, false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _withTooltip(
              'Dock or undock when you are in range of a station.',
              FilledButton.tonalIcon(
                onPressed: onDockTap,
                icon: const Icon(Icons.meeting_room_outlined),
                label: const Text('Dock'),
              ),
            ),
            const SizedBox(height: 8),
            _withTooltip(
              'Trigger sector transit at a jump gate.',
              FilledButton.tonalIcon(
                onPressed: onJumpTap,
                icon: const Icon(Icons.double_arrow_rounded),
                label: const Text('Jump'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.muted = false});

  final String label;
  final Color color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: muted
            ? Colors.black.withValues(alpha: 0.35)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: muted
              ? Colors.white.withValues(alpha: 0.14)
              : color.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: muted ? Colors.white70 : color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HudCard extends StatelessWidget {
  const _HudCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rowChildren = <Widget>[
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: const Color(0xFFF2F7FB)),
        ),
      ),
    ];
    if (trailing != null) {
      rowChildren.add(trailing!);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
        color: colors.surface.withValues(alpha: 0.72),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: rowChildren),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({
    required this.label,
    required this.value,
    required this.text,
    required this.color,
  });

  final String label;
  final double value;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Container(
                height: 12,
                color: const Color(0xFF0C121B),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: safeValue,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withValues(alpha: 0.65), color],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagMetric extends StatelessWidget {
  const _TagMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1721),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PowerRow extends StatelessWidget {
  const _PowerRow({
    required this.channel,
    required this.value,
    required this.onAdjust,
  });

  final PowerChannel channel;
  final int value;
  final void Function(int delta) onAdjust;

  @override
  Widget build(BuildContext context) {
    final color = channel.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              channel.label,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Container(
                height: 10,
                color: const Color(0xFF0C121B),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (value / 100).clamp(0.0, 1.0).toDouble(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.55), color],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _StepperButton(
            icon: Icons.remove,
            tooltip: 'Reduce ${channel.label.toLowerCase()} allocation.',
            onTap: () => onAdjust(-1),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            tooltip: 'Increase ${channel.label.toLowerCase()} allocation.',
            onTap: () => onAdjust(1),
          ),
        ],
      ),
    );
  }
}

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({
    required this.label,
    required this.tier,
    required this.maxTier,
    required this.cost,
    required this.onPressed,
    this.valueText,
  });

  final String label;
  final int tier;
  final int maxTier;
  final int cost;
  final VoidCallback? onPressed;
  final String? valueText;

  @override
  Widget build(BuildContext context) {
    final maxed = tier >= maxTier;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1721),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valueText ?? 'Tier ${tier + 1}/${maxTier + 1}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (maxed)
              const Text(
                'MAX',
                style: TextStyle(
                  color: Color(0xFF4ADE80),
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              _withTooltip(
                'Spend $cost credits to upgrade $label.',
                FilledButton.tonal(
                  onPressed: onPressed,
                  child: Text('Upgrade $cost'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _withTooltip(
      tooltip,
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          onTap();
          HapticFeedback.selectionClick();
        },
        child: Ink(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF132131),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}

class _MissionPanel extends StatelessWidget {
  const _MissionPanel({required this.game});

  final VanSoleGame game;

  @override
  Widget build(BuildContext context) {
    final active = game.activeContract;
    final dockOffer = game.currentDockOffer;
    if (active == null && dockOffer == null) {
      return const Text('No active contract and no current station offer.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active != null)
          _ContractBox(
            title: 'Active: ${active.cargoName}',
            accent: const Color(0xFF4ADE80),
            lines: [
              'Pickup: ${active.pickup.name}',
              'Deliver: ${active.destination.name}',
              'Cargo: ${active.cargoUnits} units',
              'Reward: ${game.projectedContractRewardLabel(active)}',
              active.statusDescription(game),
            ],
          ),
        if (dockOffer != null) ...[
          if (active != null) const SizedBox(height: 10),
          _ContractBox(
            title: 'Dock Offer: ${dockOffer.cargoName}',
            accent: const Color(0xFFFBBF24),
            lines: [
              'To: ${dockOffer.destination.name}',
              'Cargo: ${dockOffer.cargoUnits} units',
              'Reward: ${game.projectedContractRewardLabel(dockOffer)}',
              if (game.isDocked && game.currentDockContractsLocked)
                'Contracts locked (need >= ${VanSoleGame.contractAccessReputationFloor})',
              game.isDocked
                  ? 'Accept while docked (button or F)'
                  : 'Dock at ${dockOffer.pickup.name} to accept',
            ],
          ),
        ],
      ],
    );
  }
}

class _ContractBox extends StatelessWidget {
  const _ContractBox({
    required this.title,
    required this.lines,
    required this.accent,
  });

  final String title;
  final List<String> lines;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1721),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: accent, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == lines.length - 1 ? 0 : 3),
              child: Text(
                lines[i],
                style: const TextStyle(color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }
}

class _MarketPanel extends StatelessWidget {
  const _MarketPanel({
    required this.game,
    required this.onBuy,
    required this.onSell,
  });

  final VanSoleGame game;
  final ValueChanged<String> onBuy;
  final ValueChanged<String> onSell;

  @override
  Widget build(BuildContext context) {
    final market = game.currentDockMarket;
    if (market == null) {
      return const Text(
        'Station market uplink unavailable.',
        style: TextStyle(color: Colors.white70),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1721),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Commodity Market',
                  style: TextStyle(
                    color: Color(0xFF93C5FD),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'Hold ${game.totalCargoUsed}/${game.cargoCapacity}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Station standing: ${game.currentDockReputationLabel}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < game.commodityCatalog.length; i++) ...[
            Builder(
              builder: (context) {
                final commodity = game.commodityCatalog[i];
                final listed = market[commodity.id];
                if (listed == null) {
                  return const SizedBox.shrink();
                }
                final buy = game.currentBuyPrice(commodity.id) ?? listed;
                final sell = game.currentSellPrice(commodity.id) ?? listed;
                final owned = game.tradeUnitsForCommodity(commodity.id);
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            commodity.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Owned $owned | Buy $buy | Sell $sell',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _withTooltip(
                      'Buy one unit of ${commodity.name}.',
                      FilledButton.tonal(
                        onPressed: game.canBuyCommodity(commodity.id)
                            ? () => onBuy(commodity.id)
                            : null,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Buy'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _withTooltip(
                      'Sell one unit of ${commodity.name}.',
                      OutlinedButton(
                        onPressed: game.canSellCommodity(commodity.id)
                            ? () => onSell(commodity.id)
                            : null,
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Sell'),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (i != game.commodityCatalog.length - 1) ...[
              const SizedBox(height: 6),
              Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }
}

enum PowerChannel { engines, weapons, shields }

extension on PowerChannel {
  String get label => switch (this) {
    PowerChannel.engines => 'Engines',
    PowerChannel.weapons => 'Weapons',
    PowerChannel.shields => 'Shields',
  };

  Color get color => switch (this) {
    PowerChannel.engines => const Color(0xFF2DD4BF),
    PowerChannel.weapons => const Color(0xFFF87171),
    PowerChannel.shields => const Color(0xFF60A5FA),
  };
}

class PlayerInput {
  const PlayerInput({
    required this.up,
    required this.down,
    required this.left,
    required this.right,
    required this.fire,
    required this.boost,
  });

  final bool up;
  final bool down;
  final bool left;
  final bool right;
  final bool fire;
  final bool boost;
}

// Central simulation state for navigation, trading, combat, missions,
// reputation, save/load, and world progression.
class VanSoleGame {
  VanSoleGame() {
    _initWorld();
    _log('Boot sequence complete. Perseus Fringe traffic control online.');
    _log(
      'Sector chart uplink complete. Patrol lanes and contract relays synced.',
    );
    _log(
      'Fly to a station and press E to dock. Accept cargo contracts for credits.',
    );
  }

  static const double worldWidth = 5200;
  static const double worldHeight = 3800;
  static const double dockingRange = 120;
  static const double dockingSpeed = 40;
  static const double radarRange = 1200;
  static const double jumpRange = 140;
  static const double jumpSpeed = 75;
  static const int saveVersion = 6;
  static const int contractAccessReputationFloor = -20;
  static const List<String> _pirateHullClasses = <String>[
    'SYMLOC',
    'KADAK',
    'DAK',
    'RYNIKI',
  ];

  final math.Random _rng = math.Random(42);

  final List<StarPoint> stars = <StarPoint>[];
  final List<Station> stations = <Station>[];
  final List<PortalGate> portals = <PortalGate>[];
  final List<ResourceNode> resources = <ResourceNode>[];
  final List<PirateShip> pirates = <PirateShip>[];
  final List<Projectile> projectiles = <Projectile>[];
  final List<Blast> blasts = <Blast>[];
  final List<String> commsLog = <String>[];
  final Map<PowerChannel, int> power = <PowerChannel, int>{
    PowerChannel.engines: 35,
    PowerChannel.weapons: 30,
    PowerChannel.shields: 35,
  };
  final Map<int, CargoContract> _stationOffers = <int, CargoContract>{};
  final Map<int, Map<String, int>> _stationMarkets = <int, Map<String, int>>{};
  final Map<int, int> _stationReputation = <int, int>{};
  final Map<String, int> _tradeCargo = <String, int>{};
  final Set<int> _harvestedResourceIds = <int>{};
  final Set<String> _unlockedLoreIds = <String>{};
  final Set<int> _visitedSectors = <int>{};

  int sectorIndex = 0;
  String sectorName = 'Perseus Fringe';
  Offset playerPosition = const Offset(900, 900);
  Offset playerVelocity = Offset.zero;
  double playerFacing = -math.pi / 2;
  double playerHull = 100;
  double playerShield = 100;
  double playerEnergy = 100;
  double playerFuel = 100;
  int credits = 260;
  int cargoUsed = 0;
  int kills = 0;
  int engineUpgradeTier = 0;
  int weaponUpgradeTier = 0;
  int shieldUpgradeTier = 0;
  int cargoUpgradeTier = 0;
  int contractsDelivered = 0;
  int crossSectorContractsDelivered = 0;
  int jumpCount = 0;
  int upgradesPurchased = 0;
  int cockpitMode = 1;
  int _campaignIndex = 0;

  Station? dockedStation;
  Station? dockCandidate;
  PortalGate? jumpCandidate;
  Station? nearestStation;
  ResourceNode? nearestResource;
  ResourceNode? harvestCandidate;
  double nearestStationDistance = double.infinity;
  double nearestResourceDistance = double.infinity;
  double nearestPortalDistance = double.infinity;
  double nearestPirateDistance = double.infinity;
  CargoContract? activeContract;
  DialogueEncounter? activeEncounter;

  double _shieldRechargeDelay = 0;
  double _playerWeaponCooldown = 0;
  double _spawnTimer = 2.5;
  double _encounterTimer = 16;
  double _marketShiftTimer = 11;
  double _clock = 0;
  double _damageFlash = 0;
  double _incomingDamageDirection = 0;
  double _incomingDamageStrength = 0;
  int _audioCueSerial = 0;
  GameAudioCue? _lastAudioCue;
  int _pirateIdSeed = 0;
  int? _trackedPirateId;
  bool _suspendCampaignEvaluation = false;

  bool get isDocked => dockedStation != null;
  double get damageFlash => _damageFlash;
  double get incomingDamageDirection => _incomingDamageDirection;
  double get incomingDamageStrength => _incomingDamageStrength;
  int get audioCueSerial => _audioCueSerial;
  GameAudioCue? get lastAudioCue => _lastAudioCue;
  int? get trackedPirateId => _trackedPirateId;
  int get totalPowerAllocation =>
      power.values.fold<int>(0, (sum, value) => sum + value);
  int get cargoCapacity => 10 + (cargoUpgradeTier * 2);
  int get tradeCargoUsed =>
      _tradeCargo.values.fold<int>(0, (sum, units) => sum + units);
  int get totalCargoUsed => cargoUsed + tradeCargoUsed;
  int get freeCargoSpace => math.max(0, cargoCapacity - totalCargoUsed);
  Map<String, int> get tradeCargoManifest =>
      Map<String, int>.unmodifiable(_tradeCargo);
  List<LoreEntry> get unlockedLoreEntries => _loreCatalog
      .where((entry) => _unlockedLoreIds.contains(entry.id))
      .toList(growable: false);
  LoreEntry? get latestLoreEntry =>
      unlockedLoreEntries.isEmpty ? null : unlockedLoreEntries.last;
  double get shieldCapacity => 100 + (shieldUpgradeTier * 20);
  double get engineTierBonus => engineUpgradeTier * 0.14;
  double get weaponTierBonus => weaponUpgradeTier * 0.16;
  double get shieldTierBonus => shieldUpgradeTier * 0.16;
  List<SectorLayout> get sectorLayouts => _sectorLayouts;
  List<CommoditySpec> get commodityCatalog => _commodityCatalog;
  int reputationForStation(int stationId) => _stationReputation[stationId] ?? 0;
  String reputationBandForStation(int stationId) =>
      _reputationBand(reputationForStation(stationId));
  int get currentDockReputation =>
      dockedStation == null ? 0 : reputationForStation(dockedStation!.id);
  String get currentDockReputationLabel {
    final rep = currentDockReputation;
    final signed = rep >= 0 ? '+$rep' : '$rep';
    return '$signed (${_reputationBand(rep)})';
  }

  bool get currentDockContractsLocked =>
      isDocked && currentDockReputation < contractAccessReputationFloor;
  int get maxEngineUpgradeTier => 3;
  int get maxWeaponUpgradeTier => 3;
  int get maxShieldUpgradeTier => 3;
  int get maxCargoUpgradeTier => 4;
  int get engineUpgradeCost => 120 + engineUpgradeTier * 110;
  int get weaponUpgradeCost => 140 + weaponUpgradeTier * 125;
  int get shieldUpgradeCost => 150 + shieldUpgradeTier * 125;
  int get cargoUpgradeCost => 110 + cargoUpgradeTier * 90;
  bool get canUpgradeEngine =>
      isDocked &&
      engineUpgradeTier < maxEngineUpgradeTier &&
      credits >= engineUpgradeCost;
  bool get canUpgradeWeapons =>
      isDocked &&
      weaponUpgradeTier < maxWeaponUpgradeTier &&
      credits >= weaponUpgradeCost;
  bool get canUpgradeShields =>
      isDocked &&
      shieldUpgradeTier < maxShieldUpgradeTier &&
      credits >= shieldUpgradeCost;
  bool get canUpgradeCargo =>
      isDocked &&
      cargoUpgradeTier < maxCargoUpgradeTier &&
      credits >= cargoUpgradeCost;
  CampaignMission? get activeCampaignMission =>
      _campaignIndex < _campaignMissions.length
      ? _campaignMissions[_campaignIndex]
      : null;
  int get campaignTotalMissions => _campaignMissions.length;
  int get campaignCompletedMissions =>
      _campaignIndex.clamp(0, _campaignMissions.length).toInt();
  bool get campaignComplete => activeCampaignMission == null;
  String get campaignStatusLabel =>
      '$campaignCompletedMissions/$campaignTotalMissions';
  int get campaignRewardCredits => activeCampaignMission?.rewardCredits ?? 0;
  String get campaignTitle =>
      activeCampaignMission?.title ?? 'Campaign complete';
  String get campaignDescription =>
      activeCampaignMission?.description ??
      'All campaign objectives completed.';
  String get campaignProgressText {
    final mission = activeCampaignMission;
    if (mission == null) {
      return 'Complete';
    }
    final progress = _campaignProgressFor(mission);
    return '$progress/${mission.target}';
  }

  double get campaignProgressFraction {
    final mission = activeCampaignMission;
    if (mission == null) {
      return 1;
    }
    return (_campaignProgressFor(mission) / mission.target)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  CargoContract? get currentDockOffer =>
      dockedStation == null ? null : _stationOffers[dockedStation!.id];
  Map<String, int>? get currentDockMarket =>
      dockedStation == null ? null : _stationMarkets[dockedStation!.id];
  String? get cockpitCommsPrompt {
    if (activeEncounter != null) {
      return '* YOU ARE BEING HAILED *';
    }
    if (!isDocked && nearestStation != null && nearestStationDistance <= 560) {
      if (playerVelocity.distance <= 120) {
        return '* PRESS \'C\' TO COMMUNICATE *';
      }
      return 'OBJECT MUST VISIBLE TO COMMUNICATE';
    }
    return null;
  }

  bool get canAcceptDockContract {
    final offer = currentDockOffer;
    return isDocked &&
        offer != null &&
        activeContract == null &&
        currentDockReputation >= contractAccessReputationFloor &&
        totalCargoUsed + offer.cargoUnits <= cargoCapacity;
  }

  bool get canDeliverDockContract {
    final station = dockedStation;
    final contract = activeContract;
    if (station == null || contract == null) {
      return false;
    }
    if (!contract.pickedUp && contract.pickup.id == station.id) {
      return totalCargoUsed + contract.cargoUnits <= cargoCapacity;
    }
    return contract.destination.id == station.id && contract.pickedUp;
  }

  bool get canRepairHull => isDocked && credits >= 40 && playerHull < 99.5;
  bool get canRefuel => isDocked && credits >= 20 && playerFuel < 99.5;

  String get contractStateLabel {
    final contract = activeContract;
    if (contract == null) {
      return currentDockOffer == null ? 'Idle' : 'Offer available';
    }
    if (!contract.pickedUp) {
      return 'Pickup pending';
    }
    return 'Delivery active';
  }

  String get currentDockDescription {
    final station = dockedStation;
    if (station == null) {
      return '';
    }
    final active = activeContract;
    if (active == null) {
      return '${station.blurb} Station batteries recharge shields, energy, and fuel while docked. Dock market access is available.';
    }
    if (!active.pickedUp && active.pickup.id == station.id) {
      return 'Contract cargo is staged here. Load it before departure.';
    }
    if (active.pickedUp && active.destination.id == station.id) {
      return 'Destination port confirmed. Cargo manifest ready for delivery.';
    }
    return '${station.blurb} You can resupply here before continuing.';
  }

  int tradeUnitsForCommodity(String commodityId) =>
      _tradeCargo[commodityId] ?? 0;

  int? currentBuyPrice(String commodityId) {
    final station = dockedStation;
    if (station == null) {
      return null;
    }
    final base = currentDockMarket?[commodityId];
    if (base == null) {
      return null;
    }
    final repFactor = _marketPriceFactor(station.id, buying: true);
    return math.max(1, (base * 1.08 * repFactor).round());
  }

  int? currentSellPrice(String commodityId) {
    final station = dockedStation;
    if (station == null) {
      return null;
    }
    final base = currentDockMarket?[commodityId];
    if (base == null) {
      return null;
    }
    final repFactor = _marketPriceFactor(station.id, buying: false);
    return math.max(1, (base * 0.92 * repFactor).round());
  }

  int projectedContractReward(CargoContract contract) {
    final delta = _contractRewardDelta(
      baseReward: contract.rewardCredits,
      destinationId: contract.destination.id,
    );
    return math.max(40, contract.rewardCredits + delta);
  }

  String projectedContractRewardLabel(CargoContract contract) {
    final adjusted = projectedContractReward(contract);
    final delta = adjusted - contract.rewardCredits;
    if (delta == 0) {
      return '$adjusted cr';
    }
    final signed = delta > 0 ? '+$delta' : '$delta';
    return '$adjusted cr ($signed rep)';
  }

  bool canBuyCommodity(String commodityId) {
    final buyPrice = currentBuyPrice(commodityId);
    return isDocked &&
        buyPrice != null &&
        credits >= buyPrice &&
        freeCargoSpace > 0;
  }

  bool canSellCommodity(String commodityId) =>
      isDocked &&
      currentSellPrice(commodityId) != null &&
      tradeUnitsForCommodity(commodityId) > 0;

  String pirateContactName(PirateShip pirate) =>
      'SYMLOC ${pirate.trackingId.toString().padLeft(2, '0')}';

  String pirateHullClass(PirateShip pirate) {
    final index =
        (pirate.trackingId + (pirate.bias * 10).floor()) %
        _pirateHullClasses.length;
    return _pirateHullClasses[index];
  }

  String pirateShieldType(PirateShip pirate) {
    if (pirate.shield >= 24) {
      return 'III';
    }
    if (pirate.shield >= 14) {
      return 'II';
    }
    return 'I';
  }

  String pirateCannonType(PirateShip pirate) {
    if (pirate.bias >= 0.72) {
      return 'HEAVY';
    }
    if (pirate.bias >= 0.38) {
      return 'PULSE';
    }
    return 'LIGHT';
  }

  void setCockpitMode(int mode) {
    cockpitMode = mode.clamp(1, 6).toInt();
  }

  // Rebuild the simulation from a clean slate while preserving the authored
  // sector, station, and campaign definitions stored on the class.
  void _initWorld() {
    _harvestedResourceIds.clear();
    _unlockedLoreIds.clear();
    _visitedSectors.clear();
    _campaignIndex = 0;
    _stationOffers.clear();
    _stationMarkets.clear();
    _stationReputation.clear();
    _tradeCargo.clear();
    for (final station in _allStations) {
      _stationReputation[station.id] = 0;
    }
    for (final station in _allStations) {
      _stationMarkets.putIfAbsent(
        station.id,
        () => _generateMarketFor(station),
      );
    }
    for (final station in _allStations) {
      _stationOffers.putIfAbsent(
        station.id,
        () => _generateContractFor(station),
      );
    }
    _marketShiftTimer = 9 + _rng.nextDouble() * 12;
    _setSector(0, initial: true);
    _encounterTimer = 14 + _rng.nextDouble() * 8;
  }

  // Advance one simulation frame. Systems are stepped in a fixed order so
  // combat, docking, mission state, and HUD summaries stay deterministic.
  void update(double dt, PlayerInput input) {
    _clock += dt;
    _playerWeaponCooldown = math.max(0, _playerWeaponCooldown - dt);
    _shieldRechargeDelay = math.max(0, _shieldRechargeDelay - dt);
    _spawnTimer -= dt;
    _encounterTimer -= dt;
    _marketShiftTimer -= dt;
    _damageFlash = math.max(0, _damageFlash - dt * 2.1);
    _incomingDamageStrength = math.max(0, _incomingDamageStrength - dt * 1.75);
    _updateMarkets();

    if (activeEncounter != null) {
      _refreshDerivedState();
      return;
    }

    _updatePlayer(dt, input);
    _updatePirates(dt);
    _updateProjectiles(dt);
    _updateBlasts(dt);
    _resolveProjectileHits();
    _resolveBodyCollisions();
    _refreshDerivedState();
    _spawnPiratesIfNeeded();
    _spawnEncounterIfNeeded();
  }

  void _updatePlayer(double dt, PlayerInput input) {
    final enginePower = power[PowerChannel.engines]! / 100;
    final weaponPower = power[PowerChannel.weapons]! / 100;
    final shieldPower = power[PowerChannel.shields]! / 100;
    final effectiveEngine = (enginePower + engineTierBonus).clamp(0.0, 1.45);
    final effectiveWeapon = (weaponPower + weaponTierBonus).clamp(0.0, 1.45);
    final effectiveShield = (shieldPower + shieldTierBonus).clamp(0.0, 1.45);

    if (isDocked) {
      final station = dockedStation!;
      playerVelocity = Offset.zero;
      playerPosition = station.position + const Offset(0, 88);
      playerEnergy = _clamp(playerEnergy + dt * 26, 0, 100);
      playerShield = _clamp(
        playerShield + dt * (18 + shieldUpgradeTier * 3),
        0,
        shieldCapacity,
      );
      playerFuel = _clamp(playerFuel + dt * 9, 0, 100);
      return;
    }

    playerEnergy = _clamp(
      playerEnergy + dt * (10 + effectiveWeapon * 8),
      0,
      100,
    );
    if (_shieldRechargeDelay <= 0) {
      playerShield = _clamp(
        playerShield + dt * (3 + effectiveShield * 12),
        0,
        shieldCapacity,
      );
    }

    var thrust = Offset.zero;
    if (input.up) thrust += const Offset(0, -1);
    if (input.down) thrust += const Offset(0, 1);
    if (input.left) thrust += const Offset(-1, 0);
    if (input.right) thrust += const Offset(1, 0);

    var boosting = false;
    if (thrust != Offset.zero) {
      thrust = _normalize(thrust);
      var accel = 170 + effectiveEngine * 260;
      if (input.boost && playerFuel > 0 && playerEnergy > 4) {
        boosting = true;
        accel *= 1.65;
        playerFuel = _clamp(
          playerFuel - dt * (6.5 - effectiveEngine * 2.5),
          0,
          100,
        );
        playerEnergy = _clamp(playerEnergy - dt * 4.5, 0, 100);
      }
      playerVelocity += thrust * (accel * dt);
      playerFacing = _approachAngle(
        playerFacing,
        math.atan2(thrust.dy, thrust.dx),
        dt * 8,
      );
    }

    final drag = boosting ? 0.93 : 0.965;
    playerVelocity *= math.pow(drag, dt * 60).toDouble();

    final baseCap = 220 + effectiveEngine * 210;
    final speedCap = boosting ? baseCap * 1.55 : baseCap;
    final speed = playerVelocity.distance;
    if (speed > speedCap) {
      playerVelocity = _normalize(playerVelocity) * speedCap;
    }

    playerPosition += playerVelocity * dt;
    playerPosition = Offset(
      playerPosition.dx.clamp(40.0, worldWidth - 40.0).toDouble(),
      playerPosition.dy.clamp(40.0, worldHeight - 40.0).toDouble(),
    );

    if (playerPosition.dx <= 40 || playerPosition.dx >= worldWidth - 40) {
      playerVelocity = Offset(-playerVelocity.dx * 0.35, playerVelocity.dy);
    }
    if (playerPosition.dy <= 40 || playerPosition.dy >= worldHeight - 40) {
      playerVelocity = Offset(playerVelocity.dx, -playerVelocity.dy * 0.35);
    }

    if (input.fire) {
      _firePlayer(effectiveWeapon.toDouble());
    }
  }

  void _firePlayer(double weaponPower) {
    if (_playerWeaponCooldown > 0 || playerEnergy < 4) {
      return;
    }
    final dir = Offset(math.cos(playerFacing), math.sin(playerFacing));
    final speed = 460 + weaponPower * 220;
    final cost = 7.5 - weaponPower * 2.2;
    playerEnergy = _clamp(playerEnergy - cost, 0, 100);
    _playerWeaponCooldown =
        (0.30 - weaponPower * 0.14 - weaponUpgradeTier * 0.01)
            .clamp(0.10, 0.35)
            .toDouble();
    projectiles.add(
      Projectile(
        position: playerPosition + dir * 20,
        velocity: playerVelocity * 0.3 + dir * speed,
        ttl: 1.35,
        damage: 12 + weaponPower * 16 + weaponUpgradeTier * 2.0,
        friendly: true,
      ),
    );
    _emitCue(GameAudioCue.fire);
  }

  void _updatePirates(double dt) {
    for (final pirate in pirates) {
      pirate.fireCooldown = math.max(0, pirate.fireCooldown - dt);
      pirate.shield = _clamp(pirate.shield + dt * 4, 0, 35);

      final toPlayer = playerPosition - pirate.position;
      final distance = toPlayer.distance;
      final desiredAngle = math.atan2(toPlayer.dy, toPlayer.dx);
      pirate.angle = _approachAngle(
        pirate.angle,
        desiredAngle,
        dt * (2.2 + pirate.bias),
      );

      var accel = 0.0;
      if (distance > 240) {
        accel = 80 + pirate.bias * 40;
      }
      if (distance > 700) {
        accel += 55;
      }
      if (distance < 140) {
        accel = -60;
      }
      final forward = Offset(math.cos(pirate.angle), math.sin(pirate.angle));
      pirate.velocity += forward * (accel * dt);
      pirate.velocity *= math.pow(0.955, dt * 60).toDouble();

      final speed = pirate.velocity.distance;
      final speedCap = 150 + pirate.bias * 50;
      if (speed > speedCap) {
        pirate.velocity = _normalize(pirate.velocity) * speedCap;
      }

      pirate.position += pirate.velocity * dt;
      pirate.position = Offset(
        pirate.position.dx.clamp(50.0, worldWidth - 50.0).toDouble(),
        pirate.position.dy.clamp(50.0, worldHeight - 50.0).toDouble(),
      );

      if (!isDocked &&
          activeEncounter == null &&
          distance < 720 &&
          pirate.fireCooldown <= 0) {
        final aimError = (_rng.nextDouble() - 0.5) * (0.18 + (distance / 1400));
        final shotAngle = desiredAngle + aimError;
        final dir = Offset(math.cos(shotAngle), math.sin(shotAngle));
        projectiles.add(
          Projectile(
            position: pirate.position + dir * 16,
            velocity: pirate.velocity * 0.25 + dir * 300,
            ttl: 2.1,
            damage: 8 + _rng.nextDouble() * 5,
            friendly: false,
          ),
        );
        pirate.fireCooldown = 0.9 + _rng.nextDouble() * 0.8;
      }
    }
  }

  void _updateProjectiles(double dt) {
    for (var i = projectiles.length - 1; i >= 0; i--) {
      final projectile = projectiles[i];
      projectile.ttl -= dt;
      projectile.position += projectile.velocity * dt;

      final outOfBounds =
          projectile.position.dx < -40 ||
          projectile.position.dy < -40 ||
          projectile.position.dx > worldWidth + 40 ||
          projectile.position.dy > worldHeight + 40;
      if (projectile.ttl <= 0 || outOfBounds) {
        projectiles.removeAt(i);
      }
    }
  }

  void _updateBlasts(double dt) {
    for (var i = blasts.length - 1; i >= 0; i--) {
      blasts[i].ttl -= dt;
      if (blasts[i].ttl <= 0) {
        blasts.removeAt(i);
      }
    }
  }

  void _resolveProjectileHits() {
    for (var i = projectiles.length - 1; i >= 0; i--) {
      final shot = projectiles[i];
      if (shot.friendly) {
        PirateShip? target;
        for (final pirate in pirates) {
          if ((pirate.position - shot.position).distance <= 18) {
            target = pirate;
            break;
          }
        }
        if (target != null) {
          _damagePirate(target, shot.damage);
          blasts.add(Blast(position: shot.position, ttl: 0.18, radius: 16));
          projectiles.removeAt(i);
          continue;
        }
      } else {
        if ((playerPosition - shot.position).distance <= 18 && !isDocked) {
          _damagePlayer(shot.damage, sourcePosition: shot.position);
          blasts.add(Blast(position: shot.position, ttl: 0.16, radius: 12));
          projectiles.removeAt(i);
          continue;
        }
      }
    }

    pirates.removeWhere((pirate) => pirate.hull <= 0);
  }

  void _resolveBodyCollisions() {
    if (isDocked) {
      return;
    }
    for (final pirate in pirates) {
      final delta = playerPosition - pirate.position;
      final dist = delta.distance;
      if (dist > 0 && dist < 28) {
        final push = _normalize(delta) * (28 - dist) * 0.6;
        playerPosition += push;
        playerVelocity += push * 4;
        _damagePlayer(6, sourcePosition: pirate.position);
      }
    }
  }

  void _damagePlayer(double damage, {Offset? sourcePosition}) {
    _shieldRechargeDelay = 1.2;
    _damageFlash = 1;
    if (sourcePosition != null) {
      final incoming = sourcePosition - playerPosition;
      if (incoming.distanceSquared > 0.01) {
        _incomingDamageDirection = math.atan2(incoming.dy, incoming.dx);
        _incomingDamageStrength = (_incomingDamageStrength + 0.72).clamp(
          0.0,
          1.0,
        );
      }
    }
    _emitCue(GameAudioCue.hit);
    var remaining = damage;
    if (playerShield > 0) {
      final shieldHit = math.min(playerShield, remaining);
      playerShield -= shieldHit;
      remaining -= shieldHit;
    }
    if (remaining > 0) {
      playerHull = _clamp(playerHull - remaining, 0, 100);
      if (playerHull <= 0) {
        _handlePlayerDestroyed();
      }
    }
  }

  void _damagePirate(PirateShip pirate, double damage) {
    var remaining = damage;
    if (pirate.shield > 0) {
      final shieldHit = math.min(pirate.shield, remaining);
      pirate.shield -= shieldHit;
      remaining -= shieldHit;
    }
    if (remaining > 0) {
      pirate.hull -= remaining;
    }
    if (pirate.hull <= 0) {
      kills += 1;
      final bounty = 18 + _rng.nextInt(24);
      credits += bounty;
      final nearbyStation = _nearestStationTo(pirate.position);
      shiftStationReputation(nearbyStation.id, 2, silent: true);
      blasts.add(Blast(position: pirate.position, ttl: 0.45, radius: 34));
      _log(
        'Pirate neutralized near ${nearbyStation.name}. Bounty +$bounty cr.',
      );
      _emitCue(GameAudioCue.contract);
      _evaluateCampaignProgress();
    }
  }

  void _handlePlayerDestroyed() {
    final station = _nearestStationTo(playerPosition);
    final penalty = math.min(credits, 120);
    credits -= penalty;
    playerHull = 80;
    playerShield = _clamp(65 + shieldUpgradeTier * 8, 0, shieldCapacity);
    playerEnergy = 80;
    playerFuel = 80;
    playerVelocity = Offset.zero;
    playerPosition = station.position + const Offset(0, 88);
    dockedStation = station;
    if (activeContract != null && activeContract!.pickedUp) {
      cargoUsed = math.max(0, cargoUsed - activeContract!.cargoUnits);
    }
    if (activeContract != null) {
      shiftStationReputation(activeContract!.pickup.id, -4, silent: true);
      shiftStationReputation(activeContract!.destination.id, -6, silent: true);
      _log('Ship disabled. Active contract forfeited.');
      activeContract = null;
    }
    _log('Emergency tow to ${station.name}. Recovery fee $penalty cr.');
  }

  // Recompute all nearest-contact caches after state changes so the cockpit
  // panel, docking prompts, radar, and combat helpers read from one source.
  void _refreshDerivedState() {
    nearestStation = _nearestStationTo(playerPosition);
    nearestStationDistance =
        (nearestStation!.position - playerPosition).distance;

    nearestResource = null;
    nearestResourceDistance = double.infinity;
    for (final resource in resources) {
      final d = (resource.position - playerPosition).distance;
      if (d < nearestResourceDistance) {
        nearestResourceDistance = d;
        nearestResource = resource;
      }
    }

    nearestPirateDistance = double.infinity;
    for (final pirate in pirates) {
      final d = (pirate.position - playerPosition).distance;
      if (d < nearestPirateDistance) {
        nearestPirateDistance = d;
      }
    }

    nearestPortalDistance = double.infinity;
    PortalGate? nearestGate;
    for (final portal in portals) {
      final d = (portal.position - playerPosition).distance;
      if (d < nearestPortalDistance) {
        nearestPortalDistance = d;
        nearestGate = portal;
      }
    }

    if (!isDocked &&
        nearestStationDistance <= dockingRange &&
        playerVelocity.distance <= dockingSpeed) {
      dockCandidate = nearestStation;
    } else {
      dockCandidate = null;
    }

    if (!isDocked &&
        nearestGate != null &&
        nearestPortalDistance <= jumpRange &&
        playerVelocity.distance <= jumpSpeed) {
      jumpCandidate = nearestGate;
    } else {
      jumpCandidate = null;
    }

    if (!isDocked &&
        nearestResource != null &&
        nearestResourceDistance <= 90 &&
        playerVelocity.distance <= 70) {
      harvestCandidate = nearestResource;
    } else {
      harvestCandidate = null;
    }

    _syncTrackingTarget();
  }

  void _spawnPiratesIfNeeded() {
    if (_spawnTimer > 0) {
      return;
    }
    final desired = 4 + math.min(3, (_clock / 90).floor());
    if (pirates.length < desired) {
      pirates.add(_spawnPirate(initial: false));
      if (_rng.nextDouble() < 0.45) {
        _log('Comms: Pirate contact detected on long-range scan.');
        _emitCue(GameAudioCue.warning);
      }
    }
    _spawnTimer = 4 + _rng.nextDouble() * 5;
  }

  void _spawnEncounterIfNeeded() {
    if (activeEncounter != null || isDocked) {
      return;
    }
    if (_encounterTimer > 0) {
      return;
    }
    if (_rng.nextDouble() < 0.35 && pirates.isNotEmpty) {
      _encounterTimer = 10 + _rng.nextDouble() * 8;
      return;
    }
    activeEncounter = _buildRandomEncounter();
    cockpitMode = 3;
    _encounterTimer = 20 + _rng.nextDouble() * 22;
    _log(
      'Incoming transmission: ${activeEncounter!.title}. Choose 1-${activeEncounter!.options.length}.',
    );
    _emitCue(GameAudioCue.comms);
  }

  void _updateMarkets() {
    if (_marketShiftTimer > 0) {
      return;
    }
    _marketShiftTimer = 9 + _rng.nextDouble() * 12;
    if (_stationMarkets.isEmpty) {
      return;
    }
    final station = _allStations[_rng.nextInt(_allStations.length)];
    final market = _stationMarkets.putIfAbsent(
      station.id,
      () => _generateMarketFor(station),
    );
    final commodity = _commodityCatalog[_rng.nextInt(_commodityCatalog.length)];
    final current = market[commodity.id] ?? commodity.basePrice;
    final factor = 1 + (_rng.nextDouble() * 0.14 - 0.07);
    market[commodity.id] = math.max(1, (current * factor).round());
  }

  PirateShip _spawnPirate({required bool initial}) {
    final edge = _rng.nextInt(4);
    late Offset position;
    switch (edge) {
      case 0:
        position = Offset(_rng.nextDouble() * worldWidth, 70);
        break;
      case 1:
        position = Offset(worldWidth - 70, _rng.nextDouble() * worldHeight);
        break;
      case 2:
        position = Offset(_rng.nextDouble() * worldWidth, worldHeight - 70);
        break;
      case 3:
        position = Offset(70, _rng.nextDouble() * worldHeight);
        break;
    }

    if (!initial && (position - playerPosition).distance < 700) {
      position = Offset(
        (position.dx + worldWidth / 2) % worldWidth,
        (position.dy + worldHeight / 2) % worldHeight,
      );
    }

    return PirateShip(
      trackingId: ++_pirateIdSeed,
      position: position,
      velocity: Offset.zero,
      angle: _rng.nextDouble() * math.pi * 2,
      hull: 28 + _rng.nextDouble() * 16,
      shield: 15 + _rng.nextDouble() * 20,
      bias: _rng.nextDouble(),
    );
  }

  PirateShip? _findPirateByTrackingId(int trackingId) {
    for (final pirate in pirates) {
      if (pirate.trackingId == trackingId) {
        return pirate;
      }
    }
    return null;
  }

  void _syncTrackingTarget() {
    if (pirates.isEmpty) {
      _trackedPirateId = null;
      return;
    }
    if (_trackedPirateId != null &&
        _findPirateByTrackingId(_trackedPirateId!) != null) {
      return;
    }
    PirateShip? best;
    var bestDistance = double.infinity;
    for (final pirate in pirates) {
      final distance = (pirate.position - playerPosition).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = pirate;
      }
    }
    _trackedPirateId = best?.trackingId;
  }

  Station _nearestStationTo(Offset point) {
    Station best = stations.first;
    var bestDistance = (best.position - point).distanceSquared;
    for (var i = 1; i < stations.length; i++) {
      final station = stations[i];
      final d = (station.position - point).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = station;
      }
    }
    return best;
  }

  CargoContract _generateContractFor(Station pickup) {
    final destinations = _allStations.where((s) => s.id != pickup.id).toList();
    final destination = destinations[_rng.nextInt(destinations.length)];
    final cargoUnits = 2 + _rng.nextInt(4);
    final commodity = _commodityCatalog[_rng.nextInt(_commodityCatalog.length)];
    final crossSectorBonus = destination.sectorIndex == pickup.sectorIndex
        ? 0
        : 90;
    final pickupPrice = _stationMarkets[pickup.id]?[commodity.id];
    final destinationPrice = _stationMarkets[destination.id]?[commodity.id];
    final marketDelta = ((destinationPrice ?? 0) - (pickupPrice ?? 0))
        .clamp(-160, 240)
        .toInt();
    final reward =
        110 +
        _rng.nextInt(170) +
        (destination.id * 6) +
        crossSectorBonus +
        marketDelta;
    return CargoContract(
      id: ++_contractIdSeed,
      pickup: pickup,
      destination: destination,
      cargoUnits: cargoUnits,
      rewardCredits: math.max(80, reward),
      cargoName: commodity.name,
    );
  }

  Map<String, int> _generateMarketFor(Station station) {
    final quotes = <String, int>{};
    final sectorBias = (station.sectorIndex - 1) * 0.035;
    final stationBias = ((station.id % 9) - 4) * 0.018;
    final styleSeed = math.sin((station.id * 13) + 0.3) * 0.035;
    for (final commodity in _commodityCatalog) {
      final volatility = (commodity.volatility * (_rng.nextDouble() * 2 - 1));
      final modifier = (1 + sectorBias + stationBias + styleSeed + volatility)
          .clamp(0.62, 1.55);
      quotes[commodity.id] = math.max(
        24,
        (commodity.basePrice * modifier).round(),
      );
    }
    return quotes;
  }

  CommoditySpec? _commodityById(String commodityId) {
    for (final commodity in _commodityCatalog) {
      if (commodity.id == commodityId) {
        return commodity;
      }
    }
    return null;
  }

  LoreEntry? _loreById(String loreId) {
    for (final entry in _loreCatalog) {
      if (entry.id == loreId) {
        return entry;
      }
    }
    return null;
  }

  void _unlockLore(String loreId, {bool silent = false}) {
    final entry = _loreById(loreId);
    if (entry == null) {
      return;
    }
    if (!_unlockedLoreIds.add(loreId) || silent) {
      return;
    }
    _log('FIELD NOTE: ${entry.title} // ${entry.summary}');
  }

  double _marketPriceFactor(int stationId, {required bool buying}) {
    final rep = reputationForStation(stationId).toDouble();
    if (buying) {
      return (1 - rep * 0.004).clamp(0.68, 1.30).toDouble();
    }
    return (1 + rep * 0.003).clamp(0.78, 1.26).toDouble();
  }

  int _contractRewardDelta({
    required int baseReward,
    required int destinationId,
  }) {
    final rep = reputationForStation(destinationId);
    final raw = (baseReward * rep * 0.0035).round();
    final lower = -(baseReward ~/ 4);
    final upper = baseReward ~/ 3;
    return raw.clamp(lower, upper).toInt();
  }

  String _reputationBand(int rep) {
    if (rep <= -26) {
      return 'Hostile';
    }
    if (rep <= -9) {
      return 'Untrusted';
    }
    if (rep <= 18) {
      return 'Neutral';
    }
    if (rep <= 44) {
      return 'Trusted';
    }
    return 'Allied';
  }

  void shiftStationReputation(int stationId, int delta, {bool silent = false}) {
    if (_stationByIdOrNull(stationId) == null || delta == 0) {
      return;
    }
    final previous = reputationForStation(stationId);
    final next = (previous + delta).clamp(-40, 80).toInt();
    _stationReputation[stationId] = next;
    if (silent || next == previous) {
      return;
    }
    if ((next - previous).abs() < 5) {
      return;
    }
    final station = _stationByIdOrNull(stationId);
    if (station != null) {
      final signed = next >= 0 ? '+$next' : '$next';
      _log(
        'Standing update at ${station.name}: $signed (${_reputationBand(next)}).',
      );
    }
  }

  static int _contractIdSeed = 0;

  void toggleDocking() {
    if (isDocked) {
      final station = dockedStation!;
      dockedStation = null;
      playerPosition = station.position + const Offset(0, 145);
      playerVelocity = Offset(0, 35);
      _log('Undocking from ${station.name}.');
      _emitCue(GameAudioCue.dock);
      return;
    }
    if (dockCandidate == null) {
      _log(
        'Docking denied. Slow to under ${dockingSpeed.round()} u/s within ${dockingRange.round()} units of a station.',
      );
      _emitCue(GameAudioCue.warning);
      return;
    }
    dockedStation = dockCandidate;
    cockpitMode = 1;
    playerVelocity = Offset.zero;
    playerPosition = dockedStation!.position + const Offset(0, 88);
    _log('Docked at ${dockedStation!.name}.');
    _emitCue(GameAudioCue.dock);
    _evaluateCampaignProgress();
  }

  void attemptJump() {
    if (isDocked) {
      _log('Undock before engaging a jump gate.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final gate = jumpCandidate;
    if (gate == null) {
      _log(
        'Jump gate not ready. Slow to under ${jumpSpeed.round()} u/s within ${jumpRange.round()} units of a gate.',
      );
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (playerFuel < 8 || playerEnergy < 12) {
      _log('Jump aborted. Need at least 8% fuel and 12% energy.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    playerFuel = _clamp(playerFuel - 8, 0, 100);
    playerEnergy = _clamp(playerEnergy - 12, 0, 100);
    final target = _portalById(gate.targetPortalId, gate.targetSectorIndex);
    final exitDir = _normalize(target.exitVector);
    jumpCount += 1;
    _setSector(
      gate.targetSectorIndex,
      spawnPosition: target.position + exitDir * 170,
      initial: false,
    );
    playerVelocity = exitDir * 45;
    playerFacing = math.atan2(exitDir.dy, exitDir.dx);
    _log('Transit complete: ${gate.name} -> ${target.name} ($sectorName).');
    _emitCue(GameAudioCue.jump);
    _evaluateCampaignProgress();
  }

  void cycleTracking() {
    if (pirates.isEmpty) {
      _trackedPirateId = null;
      _log('TRACKING: no hostile contacts.');
      _emitCue(GameAudioCue.warning);
      return;
    }

    final sorted = pirates.toList()
      ..sort(
        (a, b) => (a.position - playerPosition).distance.compareTo(
          (b.position - playerPosition).distance,
        ),
      );
    var index = 0;
    if (_trackedPirateId != null) {
      final currentIndex = sorted.indexWhere(
        (pirate) => pirate.trackingId == _trackedPirateId,
      );
      if (currentIndex >= 0) {
        index = (currentIndex + 1) % sorted.length;
      }
    }
    final target = sorted[index];
    cockpitMode = 4;
    _trackedPirateId = target.trackingId;
    final range = (target.position - playerPosition).distance;
    final contact = pirateContactName(target);
    _log(
      'TRACKING: $contact ${index + 1}/${sorted.length} tagged at ${_distanceKm(range)}.',
    );
    _emitCue(GameAudioCue.comms);
  }

  void requestComms() {
    cockpitMode = 3;
    if (activeEncounter != null) {
      _log('* PRESS \'C\' TO COMMUNICATE *');
      _emitCue(GameAudioCue.comms);
      return;
    }
    if (!isDocked &&
        nearestStation != null &&
        nearestStationDistance <= 560 &&
        playerVelocity.distance <= 120) {
      _log('COMM LINK: ${nearestStation!.name} relay responding.');
      _emitCue(GameAudioCue.comms);
      return;
    }
    if (!isDocked && nearestStation != null && nearestStationDistance <= 560) {
      _log('OBJECT MUST VISIBLE TO COMMUNICATE');
      _emitCue(GameAudioCue.warning);
      return;
    }
    _log('NO RESPONSE ON ANY CHANNEL.');
    _emitCue(GameAudioCue.warning);
  }

  void harvestResource() {
    if (isDocked) {
      _log('Undock before running a harvest pass.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final node = harvestCandidate;
    if (node == null) {
      _log('No resource field in harvest range.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (freeCargoSpace < node.yieldUnits) {
      _log(
        'Insufficient cargo space for ${node.name} (${node.yieldUnits} units).',
      );
      _emitCue(GameAudioCue.warning);
      return;
    }
    final commodity = _commodityById(node.commodityId);
    if (commodity == null) {
      _log('Harvest pass failed: unknown cargo profile.');
      _emitCue(GameAudioCue.warning);
      return;
    }

    cockpitMode = 1;
    _tradeCargo.update(
      node.commodityId,
      (units) => units + node.yieldUnits,
      ifAbsent: () => node.yieldUnits,
    );
    _harvestedResourceIds.add(node.id);
    resources.removeWhere((resource) => resource.id == node.id);
    playerEnergy = _clamp(playerEnergy - 6, 0, 100);
    playerFuel = _clamp(playerFuel - 2, 0, 100);
    _unlockLore(node.loreId);
    _log(
      'Harvested ${node.name}: +${node.yieldUnits} ${commodity.name.toUpperCase()}.',
    );
    _emitCue(GameAudioCue.contract);
    _refreshDerivedState();
  }

  void tryAcceptDockContract() {
    final station = dockedStation;
    if (station == null) {
      _log('No station link active.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (activeContract != null) {
      _log('You already have an active contract.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final offer = _stationOffers[station.id];
    if (offer == null) {
      _log('No contracts available at ${station.name}.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (reputationForStation(station.id) < contractAccessReputationFloor) {
      _log(
        'Dockmaster refuses new contracts at ${station.name}. Improve standing to $contractAccessReputationFloor or higher.',
      );
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (totalCargoUsed + offer.cargoUnits > cargoCapacity) {
      _log('Insufficient cargo space for ${offer.cargoUnits} units.');
      _emitCue(GameAudioCue.warning);
      return;
    }

    activeContract = offer.copyForAcceptance();
    cockpitMode = 6;
    _stationOffers[station.id] = _generateContractFor(station);
    _log(
      'Accepted contract: ${offer.cargoName} to ${offer.destination.name} (${projectedContractRewardLabel(offer)}).',
    );
    _emitCue(GameAudioCue.contract);

    if (activeContract!.pickup.id == station.id) {
      activeContract!.pickedUp = true;
      cargoUsed += activeContract!.cargoUnits;
      _log('Cargo loaded: ${activeContract!.cargoUnits} units aboard.');
    }
  }

  void tryDeliverDockContract() {
    final station = dockedStation;
    final contract = activeContract;
    if (station == null || contract == null) {
      _log('No deliverable cargo.');
      _emitCue(GameAudioCue.warning);
      return;
    }

    if (!contract.pickedUp && contract.pickup.id == station.id) {
      if (totalCargoUsed + contract.cargoUnits > cargoCapacity) {
        _log('Insufficient cargo space to load the contract cargo.');
        _emitCue(GameAudioCue.warning);
        return;
      }
      contract.pickedUp = true;
      cargoUsed += contract.cargoUnits;
      cockpitMode = 6;
      _log('Cargo loaded for ${contract.destination.name}.');
      _emitCue(GameAudioCue.contract);
      return;
    }

    if (contract.destination.id != station.id || !contract.pickedUp) {
      _log('This station is not the contract destination.');
      _emitCue(GameAudioCue.warning);
      return;
    }

    cargoUsed = math.max(0, cargoUsed - contract.cargoUnits);
    final payout = projectedContractReward(contract);
    credits += payout;
    contractsDelivered += 1;
    if (contract.pickup.sectorIndex != contract.destination.sectorIndex) {
      crossSectorContractsDelivered += 1;
    }
    shiftStationReputation(station.id, 7, silent: true);
    if (contract.pickup.id != station.id) {
      shiftStationReputation(contract.pickup.id, 2, silent: true);
    }
    final delta = payout - contract.rewardCredits;
    final repText = delta == 0
        ? ''
        : (delta > 0 ? ' (rep bonus +$delta)' : ' (rep penalty $delta)');
    _log('Cargo delivered to ${station.name}. Payment +$payout cr$repText.');
    activeContract = null;
    cockpitMode = 6;
    _emitCue(GameAudioCue.contract);
    _evaluateCampaignProgress();
  }

  void repairHull() {
    if (!canRepairHull) {
      _log('Repair service unavailable.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    credits -= 40;
    playerHull = _clamp(playerHull + 38, 0, 100);
    _log('Hull repairs completed (-40 cr).');
    _emitCue(GameAudioCue.contract);
  }

  void refuel() {
    if (!canRefuel) {
      _log('Refuel service unavailable.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    credits -= 20;
    playerFuel = 100;
    _log('Tanks topped off (-20 cr).');
    _emitCue(GameAudioCue.contract);
  }

  void buyCommodity(String commodityId) {
    final station = dockedStation;
    final commodity = _commodityById(commodityId);
    if (station == null || commodity == null) {
      _log('Commodity market unavailable.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final price = currentBuyPrice(commodityId);
    if (price == null) {
      _log('${station.name} does not list ${commodity.name}.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (freeCargoSpace <= 0) {
      _log('Cargo hold is full.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (credits < price) {
      _log('Insufficient credits to buy ${commodity.name}.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    credits -= price;
    _tradeCargo.update(commodityId, (units) => units + 1, ifAbsent: () => 1);
    _log('Purchased ${commodity.name} (1 unit) for $price cr.');
    _emitCue(GameAudioCue.contract);
  }

  void sellCommodity(String commodityId) {
    final station = dockedStation;
    final commodity = _commodityById(commodityId);
    final units = _tradeCargo[commodityId] ?? 0;
    if (station == null || commodity == null) {
      _log('Commodity market unavailable.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (units <= 0) {
      _log('No ${commodity.name} cargo available to sell.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final price = currentSellPrice(commodityId);
    if (price == null) {
      _log('${station.name} market cannot process ${commodity.name}.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final remaining = units - 1;
    if (remaining <= 0) {
      _tradeCargo.remove(commodityId);
    } else {
      _tradeCargo[commodityId] = remaining;
    }
    credits += price;
    _log('Sold ${commodity.name} (1 unit) for $price cr.');
    _emitCue(GameAudioCue.contract);
  }

  void buyEngineUpgrade() {
    if (!isDocked) {
      _log('Dock to access outfitting services.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (engineUpgradeTier >= maxEngineUpgradeTier) {
      _log('Engines already at maximum tuning.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (credits < engineUpgradeCost) {
      _log('Insufficient credits for engine tuning.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final cost = engineUpgradeCost;
    credits -= cost;
    engineUpgradeTier += 1;
    upgradesPurchased += 1;
    _log('Engine tuning upgraded to Mk ${engineUpgradeTier + 1} (-$cost cr).');
    _emitCue(GameAudioCue.contract);
    _evaluateCampaignProgress();
  }

  void buyWeaponUpgrade() {
    if (!isDocked) {
      _log('Dock to access outfitting services.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (weaponUpgradeTier >= maxWeaponUpgradeTier) {
      _log('Weapons already at maximum calibration.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (credits < weaponUpgradeCost) {
      _log('Insufficient credits for weapon upgrades.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final cost = weaponUpgradeCost;
    credits -= cost;
    weaponUpgradeTier += 1;
    upgradesPurchased += 1;
    _log(
      'Weapon capacitors upgraded to Mk ${weaponUpgradeTier + 1} (-$cost cr).',
    );
    _emitCue(GameAudioCue.contract);
    _evaluateCampaignProgress();
  }

  void buyShieldUpgrade() {
    if (!isDocked) {
      _log('Dock to access outfitting services.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (shieldUpgradeTier >= maxShieldUpgradeTier) {
      _log('Shield array already at maximum capacity.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (credits < shieldUpgradeCost) {
      _log('Insufficient credits for shield upgrades.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final cost = shieldUpgradeCost;
    credits -= cost;
    shieldUpgradeTier += 1;
    upgradesPurchased += 1;
    playerShield = _clamp(playerShield + 20, 0, shieldCapacity);
    _log('Shield array upgraded to Mk ${shieldUpgradeTier + 1} (-$cost cr).');
    _emitCue(GameAudioCue.contract);
    _evaluateCampaignProgress();
  }

  void buyCargoUpgrade() {
    if (!isDocked) {
      _log('Dock to access outfitting services.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (cargoUpgradeTier >= maxCargoUpgradeTier) {
      _log('Cargo racks already at maximum expansion.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    if (credits < cargoUpgradeCost) {
      _log('Insufficient credits for cargo rack expansion.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final cost = cargoUpgradeCost;
    credits -= cost;
    cargoUpgradeTier += 1;
    upgradesPurchased += 1;
    _log('Cargo racks expanded to $cargoCapacity units (-$cost cr).');
    _emitCue(GameAudioCue.contract);
    _evaluateCampaignProgress();
  }

  void adjustPower(PowerChannel channel, int deltaSteps) {
    if (deltaSteps == 0) {
      return;
    }
    final stepCount = deltaSteps.abs();
    for (var i = 0; i < stepCount; i++) {
      if (deltaSteps > 0) {
        if (!_shiftPowerToward(channel)) {
          break;
        }
      } else {
        if (!_shiftPowerAway(channel)) {
          break;
        }
      }
    }
  }

  bool _shiftPowerToward(PowerChannel target) {
    if (power[target]! >= 80) {
      return false;
    }
    final donors =
        PowerChannel.values
            .where((channel) => channel != target && power[channel]! > 10)
            .toList()
          ..sort((a, b) => power[b]!.compareTo(power[a]!));
    if (donors.isEmpty) {
      return false;
    }
    power[donors.first] = power[donors.first]! - 5;
    power[target] = power[target]! + 5;
    return true;
  }

  bool _shiftPowerAway(PowerChannel source) {
    if (power[source]! <= 10) {
      return false;
    }
    final recipients =
        PowerChannel.values
            .where((channel) => channel != source && power[channel]! < 80)
            .toList()
          ..sort((a, b) => power[a]!.compareTo(power[b]!));
    if (recipients.isEmpty) {
      return false;
    }
    power[source] = power[source]! - 5;
    power[recipients.first] = power[recipients.first]! + 5;
    return true;
  }

  void _log(String text) {
    final totalSeconds = _clock.floor();
    final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (totalSeconds % 60).toString().padLeft(2, '0');
    commsLog.insert(0, '[$mm:$ss] $text');
    if (commsLog.length > 10) {
      commsLog.removeRange(10, commsLog.length);
    }
  }

  int _campaignProgressFor(CampaignMission mission) {
    switch (mission.goalType) {
      case CampaignGoalType.dockStation:
        return dockedStation?.id == mission.stationId ? 1 : 0;
      case CampaignGoalType.deliverContracts:
        return contractsDelivered;
      case CampaignGoalType.killPirates:
        return kills;
      case CampaignGoalType.visitSector:
        return _visitedSectors.contains(mission.sectorIndex) ? 1 : 0;
      case CampaignGoalType.buyUpgrades:
        return upgradesPurchased;
      case CampaignGoalType.crossSectorDeliveries:
        return crossSectorContractsDelivered;
    }
  }

  void reevaluateCampaignProgress() => _evaluateCampaignProgress();

  void _evaluateCampaignProgress({
    bool grantRewards = true,
    bool emitLogs = true,
  }) {
    if (_suspendCampaignEvaluation) {
      return;
    }
    var advanced = false;
    while (true) {
      final mission = activeCampaignMission;
      if (mission == null) {
        break;
      }
      if (_campaignProgressFor(mission) < mission.target) {
        break;
      }
      _campaignIndex += 1;
      if (grantRewards && mission.rewardCredits > 0) {
        credits += mission.rewardCredits;
      }
      if (emitLogs) {
        final rewardText = grantRewards && mission.rewardCredits > 0
            ? ' (+${mission.rewardCredits} cr)'
            : '';
        _log('Campaign objective complete: ${mission.title}$rewardText.');
      }
      advanced = true;
    }
    if (!advanced) {
      return;
    }
    if (emitLogs && campaignComplete) {
      _log('Campaign arc complete. Continue free-roam contracts and combat.');
    }
    if (emitLogs || grantRewards) {
      _emitCue(GameAudioCue.contract);
    }
  }

  void chooseDialogueOption(int index) {
    final encounter = activeEncounter;
    if (encounter == null) {
      return;
    }
    if (index < 0 || index >= encounter.options.length) {
      _log('Invalid comms response.');
      _emitCue(GameAudioCue.warning);
      return;
    }
    final option = encounter.options[index];
    credits = math.max(0, credits + option.creditsDelta);
    playerFuel = _clamp(playerFuel + option.fuelDelta, 0, 100);
    playerEnergy = _clamp(playerEnergy + option.energyDelta, 0, 100);
    playerShield = _clamp(playerShield + option.shieldDelta, 0, shieldCapacity);
    if (option.hullDelta < 0) {
      _damagePlayer(-option.hullDelta);
    } else if (option.hullDelta > 0) {
      playerHull = _clamp(playerHull + option.hullDelta, 0, 100);
    }
    for (var i = 0; i < option.spawnPirates; i++) {
      pirates.add(_spawnPirate(initial: false));
    }
    _log(option.resultLog);
    activeEncounter = null;
    _encounterTimer = 18 + _rng.nextDouble() * 20;
    _emitCue(GameAudioCue.comms);
  }

  // Save codes are plain JSON so they remain portable across every target
  // platform without depending on platform-specific storage APIs.
  String exportSaveCode() => jsonEncode(_toSaveMap());

  // Importing rebuilds sector state, cargo, progression, and reputation from
  // the portable save-code map while validating version compatibility first.
  void importSaveCode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Save code is not a JSON object.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final version = (map['version'] as num?)?.toInt() ?? 0;
    if (version < 1 || version > saveVersion) {
      throw FormatException(
        'Unsupported save version $version (expected 1-$saveVersion).',
      );
    }

    final targetSector = (map['sectorIndex'] as num?)?.toInt() ?? 0;
    _harvestedResourceIds.clear();
    final harvestedRaw = map['harvestedResourceIds'];
    if (harvestedRaw is List) {
      for (final value in harvestedRaw) {
        if (value is num) {
          _harvestedResourceIds.add(value.toInt());
        }
      }
    }
    _unlockedLoreIds.clear();
    final loreRaw = map['unlockedLoreIds'];
    if (loreRaw is List) {
      for (final value in loreRaw) {
        if (value is String && _loreById(value) != null) {
          _unlockedLoreIds.add(value);
        }
      }
    }
    _suspendCampaignEvaluation = true;
    try {
      _setSector(targetSector, initial: true);
    } finally {
      _suspendCampaignEvaluation = false;
    }

    _clock = (map['clock'] as num?)?.toDouble() ?? _clock;
    playerFacing = (map['playerFacing'] as num?)?.toDouble() ?? playerFacing;
    engineUpgradeTier =
        ((map['engineUpgradeTier'] as num?)?.toInt() ?? engineUpgradeTier)
            .clamp(0, maxEngineUpgradeTier)
            .toInt();
    weaponUpgradeTier =
        ((map['weaponUpgradeTier'] as num?)?.toInt() ?? weaponUpgradeTier)
            .clamp(0, maxWeaponUpgradeTier)
            .toInt();
    shieldUpgradeTier =
        ((map['shieldUpgradeTier'] as num?)?.toInt() ?? shieldUpgradeTier)
            .clamp(0, maxShieldUpgradeTier)
            .toInt();
    cargoUpgradeTier =
        ((map['cargoUpgradeTier'] as num?)?.toInt() ?? cargoUpgradeTier)
            .clamp(0, maxCargoUpgradeTier)
            .toInt();
    playerHull = _clamp((map['playerHull'] as num?) ?? playerHull, 0, 100);
    playerShield = _clamp(
      (map['playerShield'] as num?) ?? playerShield,
      0,
      shieldCapacity,
    );
    playerEnergy = _clamp(
      (map['playerEnergy'] as num?) ?? playerEnergy,
      0,
      100,
    );
    playerFuel = _clamp((map['playerFuel'] as num?) ?? playerFuel, 0, 100);
    credits = (map['credits'] as num?)?.toInt() ?? credits;
    _tradeCargo.clear();
    final tradeCargoRaw = map['tradeCargo'];
    if (tradeCargoRaw is Map) {
      for (final entry in tradeCargoRaw.entries) {
        final commodityId = entry.key.toString();
        if (_commodityById(commodityId) == null) {
          continue;
        }
        final unitsRaw = entry.value;
        if (unitsRaw is num) {
          final units = unitsRaw.toInt();
          if (units > 0) {
            _tradeCargo[commodityId] = units.clamp(0, cargoCapacity).toInt();
          }
        }
      }
    }
    cargoUsed = ((map['cargoUsed'] as num?)?.toInt() ?? cargoUsed)
        .clamp(0, math.max(0, cargoCapacity - tradeCargoUsed))
        .toInt();
    kills = (map['kills'] as num?)?.toInt() ?? kills;
    contractsDelivered = (map['contractsDelivered'] as num?)?.toInt() ?? 0;
    crossSectorContractsDelivered =
        (map['crossSectorContractsDelivered'] as num?)?.toInt() ?? 0;
    jumpCount = (map['jumpCount'] as num?)?.toInt() ?? 0;
    upgradesPurchased =
        (map['upgradesPurchased'] as num?)?.toInt() ??
        (engineUpgradeTier +
            weaponUpgradeTier +
            shieldUpgradeTier +
            cargoUpgradeTier);
    cockpitMode = ((map['cockpitMode'] as num?)?.toInt() ?? cockpitMode)
        .clamp(1, 6)
        .toInt();
    _campaignIndex = ((map['campaignIndex'] as num?)?.toInt() ?? 0)
        .clamp(0, campaignTotalMissions)
        .toInt();
    _visitedSectors
      ..clear()
      ..add(targetSector);
    final visitedRaw = map['visitedSectors'];
    if (visitedRaw is List) {
      for (final v in visitedRaw) {
        if (v is num) {
          _visitedSectors.add(v.toInt());
        }
      }
    }

    final pos = map['playerPosition'];
    if (pos is Map) {
      playerPosition = Offset(
        ((pos['x'] as num?) ?? playerPosition.dx).toDouble(),
        ((pos['y'] as num?) ?? playerPosition.dy).toDouble(),
      );
    }
    final vel = map['playerVelocity'];
    if (vel is Map) {
      playerVelocity = Offset(
        ((vel['x'] as num?) ?? playerVelocity.dx).toDouble(),
        ((vel['y'] as num?) ?? playerVelocity.dy).toDouble(),
      );
    }

    final powerMap = map['power'];
    if (powerMap is Map) {
      for (final channel in PowerChannel.values) {
        final key = channel.name;
        final rawValue = powerMap[key];
        if (rawValue is num) {
          power[channel] = (rawValue.toInt()).clamp(10, 80).toInt();
        }
      }
      _rebalancePower();
    }

    _stationMarkets.clear();
    final markets = map['stationMarkets'];
    if (markets is Map) {
      for (final stationEntry in markets.entries) {
        final stationId = int.tryParse(stationEntry.key.toString());
        if (stationId == null) {
          continue;
        }
        if (!_allStations.any((station) => station.id == stationId)) {
          continue;
        }
        final stationMapRaw = stationEntry.value;
        if (stationMapRaw is! Map) {
          continue;
        }
        final quotes = <String, int>{};
        for (final quoteEntry in stationMapRaw.entries) {
          final commodityId = quoteEntry.key.toString();
          if (_commodityById(commodityId) == null) {
            continue;
          }
          final quoteValue = quoteEntry.value;
          if (quoteValue is num) {
            quotes[commodityId] = quoteValue.toInt().clamp(1, 9999).toInt();
          }
        }
        if (quotes.isNotEmpty) {
          _stationMarkets[stationId] = quotes;
        }
      }
    }
    for (final station in _allStations) {
      _stationMarkets.putIfAbsent(
        station.id,
        () => _generateMarketFor(station),
      );
    }
    _stationReputation.clear();
    final repRaw = map['stationReputation'];
    if (repRaw is Map) {
      for (final entry in repRaw.entries) {
        final stationId = int.tryParse(entry.key.toString());
        if (stationId == null || _stationByIdOrNull(stationId) == null) {
          continue;
        }
        final value = entry.value;
        if (value is num) {
          _stationReputation[stationId] = value.toInt().clamp(-40, 80).toInt();
        }
      }
    }
    for (final station in _allStations) {
      _stationReputation.putIfAbsent(station.id, () => 0);
    }
    _stationOffers.clear();
    final offers = map['stationOffers'];
    if (offers is List) {
      for (final item in offers) {
        if (item is Map) {
          final offer = _contractFromMap(Map<String, dynamic>.from(item));
          _stationOffers[offer.pickup.id] = offer;
        }
      }
    }
    for (final station in _allStations) {
      _stationOffers.putIfAbsent(
        station.id,
        () => _generateContractFor(station),
      );
    }

    final active = map['activeContract'];
    activeContract = active is Map
        ? _contractFromMap(Map<String, dynamic>.from(active))
        : null;

    final dockedId = (map['dockedStationId'] as num?)?.toInt();
    dockedStation = dockedId == null
        ? null
        : _stationIfInCurrentSector(dockedId);
    if (dockedStation != null) {
      playerVelocity = Offset.zero;
      playerPosition = dockedStation!.position + const Offset(0, 88);
    }

    commsLog.clear();
    final logLines = map['commsLog'];
    if (logLines is List) {
      for (final line in logLines) {
        if (line is String) {
          commsLog.add(line);
        }
      }
    }
    if (commsLog.isEmpty) {
      _log('Save restored.');
    } else {
      _log('Save restored in $sectorName.');
    }

    activeEncounter = null;
    projectiles.clear();
    blasts.clear();
    pirates
      ..clear()
      ..addAll(
        List.generate(3 + _rng.nextInt(2), (_) => _spawnPirate(initial: true)),
      );
    _trackedPirateId = (map['trackedPirateId'] as num?)?.toInt();
    _refreshDerivedState();
    _evaluateCampaignProgress(grantRewards: false, emitLogs: false);
    _emitCue(GameAudioCue.contract);
  }

  Map<String, dynamic> _toSaveMap() {
    return <String, dynamic>{
      'version': saveVersion,
      'sectorIndex': sectorIndex,
      'clock': _clock,
      'playerPosition': {'x': playerPosition.dx, 'y': playerPosition.dy},
      'playerVelocity': {'x': playerVelocity.dx, 'y': playerVelocity.dy},
      'playerFacing': playerFacing,
      'playerHull': playerHull,
      'playerShield': playerShield,
      'playerEnergy': playerEnergy,
      'playerFuel': playerFuel,
      'credits': credits,
      'cargoCapacity': cargoCapacity,
      'cargoUsed': cargoUsed,
      'tradeCargo': _tradeCargo,
      'kills': kills,
      'contractsDelivered': contractsDelivered,
      'crossSectorContractsDelivered': crossSectorContractsDelivered,
      'jumpCount': jumpCount,
      'upgradesPurchased': upgradesPurchased,
      'cockpitMode': cockpitMode,
      'campaignIndex': _campaignIndex,
      'visitedSectors': _visitedSectors.toList()..sort(),
      'engineUpgradeTier': engineUpgradeTier,
      'weaponUpgradeTier': weaponUpgradeTier,
      'shieldUpgradeTier': shieldUpgradeTier,
      'cargoUpgradeTier': cargoUpgradeTier,
      'dockedStationId': dockedStation?.id,
      'trackedPirateId': _trackedPirateId,
      'power': {
        for (final channel in PowerChannel.values) channel.name: power[channel],
      },
      'activeContract': activeContract == null
          ? null
          : _contractToMap(activeContract!),
      'stationOffers': _stationOffers.values.map(_contractToMap).toList(),
      'stationMarkets': {
        for (final entry in _stationMarkets.entries)
          '${entry.key}': Map<String, int>.from(entry.value),
      },
      'stationReputation': {
        for (final entry in _stationReputation.entries)
          '${entry.key}': entry.value,
      },
      'harvestedResourceIds': _harvestedResourceIds.toList()..sort(),
      'unlockedLoreIds': _unlockedLoreIds.toList()..sort(),
      'commsLog': commsLog.take(10).toList(),
    };
  }

  Map<String, dynamic> _contractToMap(CargoContract contract) {
    return <String, dynamic>{
      'id': contract.id,
      'pickupId': contract.pickup.id,
      'destinationId': contract.destination.id,
      'cargoUnits': contract.cargoUnits,
      'rewardCredits': contract.rewardCredits,
      'cargoName': contract.cargoName,
      'pickedUp': contract.pickedUp,
    };
  }

  CargoContract _contractFromMap(Map<String, dynamic> map) {
    final id = (map['id'] as num?)?.toInt() ?? ++_contractIdSeed;
    _contractIdSeed = math.max(_contractIdSeed, id);
    return CargoContract(
      id: id,
      pickup: _stationById((map['pickupId'] as num?)?.toInt() ?? 1),
      destination: _stationById((map['destinationId'] as num?)?.toInt() ?? 2),
      cargoUnits: (map['cargoUnits'] as num?)?.toInt() ?? 2,
      rewardCredits: (map['rewardCredits'] as num?)?.toInt() ?? 100,
      cargoName: (map['cargoName'] as String?) ?? 'Cargo',
      pickedUp: (map['pickedUp'] as bool?) ?? false,
    );
  }

  void _setSector(int index, {Offset? spawnPosition, required bool initial}) {
    if (index < 0 || index >= _sectorLayouts.length) {
      throw RangeError.range(index, 0, _sectorLayouts.length - 1, 'index');
    }
    final layout = _sectorLayouts[index];
    final firstVisitToSector = _visitedSectors.add(index);
    sectorIndex = index;
    sectorName = layout.name;
    stations
      ..clear()
      ..addAll(layout.stations);
    portals
      ..clear()
      ..addAll(layout.portals);
    resources
      ..clear()
      ..addAll(
        layout.resources.where(
          (resource) => !_harvestedResourceIds.contains(resource.id),
        ),
      );
    _rebuildStars(layout.starSeed);

    dockedStation = null;
    dockCandidate = null;
    jumpCandidate = null;
    activeEncounter = null;
    projectiles.clear();
    blasts.clear();

    if (spawnPosition != null) {
      playerPosition = spawnPosition;
    } else {
      playerPosition = initial
          ? switch (index) {
              0 => const Offset(1640, 1320),
              1 => const Offset(2140, 1760),
              _ => const Offset(1960, 1720),
            }
          : stations.first.position + const Offset(0, 180);
    }

    pirates
      ..clear()
      ..addAll(List.generate(4, (_) => _spawnPirate(initial: true)));
    _spawnTimer = 3 + _rng.nextDouble() * 2;
    _encounterTimer = 12 + _rng.nextDouble() * 12;

    _refreshDerivedState();
    if (!initial) {
      _log('Sector transit complete: $sectorName.');
    }
    if (firstVisitToSector) {
      _unlockLore('sector-$index', silent: initial);
    }
    if (firstVisitToSector && !initial) {
      _evaluateCampaignProgress();
    }
  }

  void _rebuildStars(int seed) {
    final r = math.Random(seed);
    stars.clear();
    for (var i = 0; i < 240; i++) {
      stars.add(
        StarPoint(
          position: Offset(
            r.nextDouble() * worldWidth,
            r.nextDouble() * worldHeight,
          ),
          radius: r.nextDouble() * 1.8 + 0.4,
          alpha: r.nextDouble() * 0.55 + 0.15,
          tint: r.nextInt(3),
        ),
      );
    }
  }

  void _emitCue(GameAudioCue cue) {
    _lastAudioCue = cue;
    _audioCueSerial += 1;
  }

  void _rebalancePower() {
    for (final channel in PowerChannel.values) {
      power[channel] = (power[channel] ?? 30).clamp(10, 80).toInt();
    }
    while (totalPowerAllocation > 100) {
      final donor = PowerChannel.values.reduce(
        (a, b) => power[a]! > power[b]! ? a : b,
      );
      if (power[donor]! <= 10) break;
      power[donor] = power[donor]! - 5;
    }
    while (totalPowerAllocation < 100) {
      final receiver = PowerChannel.values.reduce(
        (a, b) => power[a]! < power[b]! ? a : b,
      );
      if (power[receiver]! >= 80) break;
      power[receiver] = power[receiver]! + 5;
    }
  }

  DialogueEncounter _buildRandomEncounter() {
    final stationName = nearestStation?.name ?? 'unknown relay';
    final contract = activeContract;
    final templates = <DialogueEncounter>[
      DialogueEncounter(
        title: 'Distress Beacon',
        body:
            'A damaged courier near $stationName requests fuel transfer and escort clearance.',
        options: [
          DialogueOption(
            label: 'Transfer fuel and credits',
            creditsDelta: 37,
            fuelDelta: -8,
            resultLog:
                'You assist the courier. A grateful broker wires 55 cr after docking.',
          ),
          DialogueOption(
            label: 'Offer navigation telemetry only',
            energyDelta: -6,
            resultLog:
                'Telemetry uplink sent. Small goodwill stipend received (+18 cr).',
            creditsDelta: 18,
          ),
          DialogueOption(
            label: 'Ignore beacon',
            resultLog: 'You ignore the beacon and continue on course.',
          ),
        ],
      ),
      DialogueEncounter(
        title: 'Trader Hail',
        body:
            'A free trader offers black-market shield capacitors and rumors of pirate patrols.',
        options: [
          DialogueOption(
            label: 'Buy capacitors (24 cr) and recharge shields',
            creditsDelta: -24,
            shieldDelta: 26,
            resultLog: 'Capacitors installed. Shields spike upward.',
          ),
          DialogueOption(
            label: 'Sell route intel (+30 cr)',
            creditsDelta: 30,
            spawnPirates: 1,
            resultLog:
                'Trader pays for intel, but leaked routes attract a pirate contact.',
          ),
          DialogueOption(
            label: 'Decline and move on',
            resultLog: 'You decline the trade.',
          ),
        ],
      ),
      DialogueEncounter(
        title: 'Patrol Scan',
        body:
            'Regional patrol requests an identification scan${contract == null ? '' : ' and asks about your cargo manifest'}.',
        options: [
          DialogueOption(
            label: 'Comply with scan',
            resultLog:
                'Patrol clears your transponder and marks nearby pirates on your tac display.',
            energyDelta: 4,
          ),
          DialogueOption(
            label: 'Bribe patrol dispatcher (+/- credits)',
            creditsDelta: -12,
            resultLog:
                'The dispatcher takes your credits and quietly shares gate traffic timings.',
            fuelDelta: 3,
          ),
          DialogueOption(
            label: 'Spoof transponder',
            spawnPirates: 1,
            resultLog: 'Spoof detected. Hostile contact appears on local scan.',
            energyDelta: -10,
          ),
        ],
      ),
      DialogueEncounter(
        title: 'Salvage Drift',
        body:
            'A shattered hull section tumbles through the lane. Sensors detect recoverable materials.',
        options: [
          DialogueOption(
            label: 'Conduct salvage pass',
            creditsDelta: 42,
            hullDelta: -4,
            resultLog:
                'You recover salvage worth 42 cr but scrape the hull during retrieval.',
          ),
          DialogueOption(
            label: 'Ping salvage coordinates to station control',
            creditsDelta: 20,
            resultLog:
                'Station control records your report and pays a finder fee.',
          ),
          DialogueOption(
            label: 'Avoid debris field',
            resultLog: 'You steer clear of the debris field.',
          ),
        ],
      ),
    ];

    return templates[_rng.nextInt(templates.length)];
  }

  static const List<CommoditySpec> _commodityCatalog = <CommoditySpec>[
    CommoditySpec(
      id: 'med_supplies',
      name: 'Medical Supplies',
      basePrice: 86,
      volatility: 0.20,
    ),
    CommoditySpec(
      id: 'fusion_coils',
      name: 'Fusion Coils',
      basePrice: 132,
      volatility: 0.27,
    ),
    CommoditySpec(
      id: 'ore_samples',
      name: 'Ore Samples',
      basePrice: 64,
      volatility: 0.16,
    ),
    CommoditySpec(
      id: 'nav_components',
      name: 'Nav Components',
      basePrice: 112,
      volatility: 0.22,
    ),
    CommoditySpec(
      id: 'cryo_foodstock',
      name: 'Cryo Foodstock',
      basePrice: 72,
      volatility: 0.14,
    ),
    CommoditySpec(
      id: 'survey_drones',
      name: 'Survey Drones',
      basePrice: 148,
      volatility: 0.30,
    ),
    CommoditySpec(
      id: 'shield_emitters',
      name: 'Shield Emitters',
      basePrice: 168,
      volatility: 0.25,
    ),
    CommoditySpec(
      id: 'encrypted_data',
      name: 'Encrypted Data Core',
      basePrice: 122,
      volatility: 0.31,
    ),
  ];

  static const List<LoreEntry> _loreCatalog = <LoreEntry>[
    LoreEntry(
      id: 'sector-0',
      title: 'Perseus Fringe',
      summary:
          'Freight lanes, military checkpoints, and stripped mining routes.',
      body:
          'The Fringe looks civilized from orbit, but every station out here runs on shortages, favors, and salvage. Army logistics keep the lanes open while traders strip the dead belts for anything that can still be sold.',
    ),
    LoreEntry(
      id: 'sector-1',
      title: 'Cygnus Reach',
      summary:
          'A richer corridor where private docks and patrol contracts overlap.',
      body:
          'Cygnus Reach is where civilian money and military necessity meet. The dockyards buy hardware, mercenaries sell protection, and every jump-lane rumor turns into work for somebody desperate enough to chase it.',
    ),
    LoreEntry(
      id: 'sector-2',
      title: 'Outer Survey',
      summary:
          'Sparse territory littered with anomalies and half-finished research sites.',
      body:
          'Outer Survey is thinly held space. Stations here survive by mapping strange signals, stripping old installations, and betting that whatever lies beyond the survey perimeter is worth the risk of finding first.',
    ),
    LoreEntry(
      id: 'lore-fringe-vein',
      title: 'Fringe Ore Vein',
      summary: 'This belt still carries rare industrial traces.',
      body:
          'The rocks near TATELUS are not natural alone. Old extraction charges cracked this belt decades ago, leaving clean seams that still carry useful alloy dust and machine-grade ore.',
    ),
    LoreEntry(
      id: 'lore-redlic-wreck',
      title: 'Redlic Wreckage',
      summary:
          'Destroyed convoy hardware keeps turning up near refinery space.',
      body:
          'Refinery pilots say Redlic always looks safe until the debris starts glittering in the floodlights. Too many freighters have died here with cargo holds full of expensive hardware.',
    ),
    LoreEntry(
      id: 'lore-reach-crystal',
      title: 'Reach Crystal Bloom',
      summary: 'Shield-tuned crystal growth around a cold pocket.',
      body:
          'The crystal bloom in Cygnus Reach bends scanner returns and stores charge in layered sheets. Engineers cut it down for emitter tuning, but scientists still argue over whether the structure is grown or manufactured.',
    ),
    LoreEntry(
      id: 'lore-reach-salvage',
      title: 'Privateer Debris',
      summary: 'Black-market survey gear mixed into a broken escort hull.',
      body:
          'Most of the wreck is scrap, but the surviving pods are packed with survey drones and cracked nav modules. Somebody moved expensive equipment through this lane and did not make it home.',
    ),
    LoreEntry(
      id: 'lore-survey-relic',
      title: 'Survey Relic',
      summary: 'A sealed object with older telemetry than the local stations.',
      body:
          'The relic does not match current station fabrication standards. Its internal clock drift suggests it has been cold and inert for a very long time, long before the current survey chain was built.',
    ),
    LoreEntry(
      id: 'lore-survey-cradle',
      title: 'Cryo Cradle Cache',
      summary: 'A cargo shell built for long-duration emergency storage.',
      body:
          'The cradle still holds cryo stock and med packs in vacuum-tight cells. Whoever staged it expected a remote crew to return later. They never did.',
    ),
  ];

  static final List<CampaignMission> _campaignMissions = <CampaignMission>[
    CampaignMission(
      title: 'Report to Obelisk Prime',
      description: 'Dock at OBELISK PRIME to receive your first assignment.',
      goalType: CampaignGoalType.dockStation,
      target: 1,
      stationId: 1,
      rewardCredits: 120,
    ),
    CampaignMission(
      title: 'Run Freight',
      description: 'Complete one cargo delivery contract.',
      goalType: CampaignGoalType.deliverContracts,
      target: 1,
      rewardCredits: 180,
    ),
    CampaignMission(
      title: 'Clear Raiders',
      description: 'Destroy three pirate ships threatening local trade lanes.',
      goalType: CampaignGoalType.killPirates,
      target: 3,
      rewardCredits: 220,
    ),
    CampaignMission(
      title: 'Transit to Orion Reach',
      description: 'Use a jump gate to enter the ORION REACH sector.',
      goalType: CampaignGoalType.visitSector,
      target: 1,
      sectorIndex: 1,
      rewardCredits: 260,
    ),
    CampaignMission(
      title: 'Field Upgrades',
      description: 'Purchase two ship upgrades while docked.',
      goalType: CampaignGoalType.buyUpgrades,
      target: 2,
      rewardCredits: 280,
    ),
    CampaignMission(
      title: 'Cross-Sector Courier',
      description: 'Finish one cross-sector cargo contract.',
      goalType: CampaignGoalType.crossSectorDeliveries,
      target: 1,
      rewardCredits: 360,
    ),
    CampaignMission(
      title: 'Outer Survey Contact',
      description: 'Reach DEEP SURVEY and dock at SILICA station.',
      goalType: CampaignGoalType.dockStation,
      target: 1,
      stationId: 24,
      rewardCredits: 500,
    ),
  ];

  static final List<SectorLayout> _sectorLayouts = <SectorLayout>[
    SectorLayout(
      name: 'Aethelgard Fringe',
      starSeed: 101,
      stations: [
        Station(
          id: 1,
          sectorIndex: 0,
          name: 'OBELISK PRIME',
          position: Offset(820, 920),
          color: Color(0xFF60A5FA),
          blurb: 'Army logistics base and patrol waypoint.',
        ),
        Station(
          id: 2,
          sectorIndex: 0,
          name: 'CORVUS DOCK',
          position: Offset(1800, 600),
          color: Color(0xFF34D399),
          blurb: 'Trade exchange with heavy civilian traffic.',
        ),
        Station(
          id: 3,
          sectorIndex: 0,
          name: 'HELIOS FORGE',
          position: Offset(3300, 950),
          color: Color(0xFFFBBF24),
          blurb: 'Mining outpost buying industrial equipment.',
        ),
        Station(
          id: 4,
          sectorIndex: 0,
          name: 'NEW KHYBER',
          position: Offset(4100, 2600),
          color: Color(0xFFF472B6),
          blurb: 'Independent habitat. Pirate activity reported nearby.',
        ),
        Station(
          id: 5,
          sectorIndex: 0,
          name: 'VANGUARD SECUNDUS',
          position: Offset(2200, 3050),
          color: Color(0xFF93C5FD),
          blurb: 'Orbital refinery and freight relay.',
        ),
        Station(
          id: 6,
          sectorIndex: 0,
          name: 'AEON PLATFORM',
          position: Offset(920, 2850),
          color: Color(0xFFA78BFA),
          blurb: 'Research platform with limited docking bays.',
        ),
      ],
      portals: [
        PortalGate(
          id: 1001,
          sectorIndex: 0,
          targetSectorIndex: 1,
          targetPortalId: 2001,
          name: 'Aethelgard Gate',
          position: Offset(4860, 460),
          exitVector: Offset(-1, 0.2),
          color: Color(0xFFA78BFA),
        ),
      ],
      resources: [
        ResourceNode(
          id: 10001,
          sectorIndex: 0,
          name: 'AETHELGARD VEIN',
          kind: ResourceKind.ore,
          position: Offset(1480, 1010),
          color: Color(0xFFE5B54D),
          commodityId: 'ore_samples',
          yieldUnits: 2,
          loreId: 'lore-fringe-vein',
          scanSummary: 'Industrial ore seam cracked open by older charges.',
        ),
        ResourceNode(
          id: 10002,
          sectorIndex: 0,
          name: 'VANGUARD WRECK',
          kind: ResourceKind.salvage,
          position: Offset(2480, 2860),
          color: Color(0xFF93C5FD),
          commodityId: 'fusion_coils',
          yieldUnits: 1,
          loreId: 'lore-vanguard-wreck',
          scanSummary: 'Convoy debris with intact power hardware.',
        ),
      ],
    ),
    SectorLayout(
      name: 'Orion Reach',
      starSeed: 202,
      stations: [
        Station(
          id: 11,
          sectorIndex: 1,
          name: 'CYGNAL',
          position: Offset(820, 700),
          color: Color(0xFF22D3EE),
          blurb: 'Civilian anchor station with dense trade traffic.',
        ),
        Station(
          id: 12,
          sectorIndex: 1,
          name: 'TARTARUS OUTPOST',
          position: Offset(2500, 820),
          color: Color(0xFFFB7185),
          blurb: 'Private dockyards and mercenary contracts.',
        ),
        Station(
          id: 13,
          sectorIndex: 1,
          name: 'IRONCLAD POST',
          position: Offset(3900, 1280),
          color: Color(0xFFF59E0B),
          blurb: 'Industrial processor buying ore and machine parts.',
        ),
        Station(
          id: 14,
          sectorIndex: 1,
          name: 'LUMEN RELAY',
          position: Offset(1700, 2830),
          color: Color(0xFF4ADE80),
          blurb: 'Listening post monitoring jump-lane chatter.',
        ),
        Station(
          id: 15,
          sectorIndex: 1,
          name: 'HAVEN',
          position: Offset(4160, 2860),
          color: Color(0xFFF472B6),
          blurb: 'Remote station with unstable gate harmonics.',
        ),
      ],
      portals: [
        PortalGate(
          id: 2001,
          sectorIndex: 1,
          targetSectorIndex: 0,
          targetPortalId: 1001,
          name: 'Orion Gate',
          position: Offset(380, 470),
          exitVector: Offset(1, 0.15),
          color: Color(0xFFA78BFA),
        ),
        PortalGate(
          id: 2002,
          sectorIndex: 1,
          targetSectorIndex: 2,
          targetPortalId: 3001,
          name: 'Reach Spur',
          position: Offset(4850, 3350),
          exitVector: Offset(-1, -0.1),
          color: Color(0xFF22D3EE),
        ),
      ],
      resources: [
        ResourceNode(
          id: 20001,
          sectorIndex: 1,
          name: 'CRYSTAL BLOOM',
          kind: ResourceKind.crystal,
          position: Offset(2060, 1470),
          color: Color(0xFF6EE7F9),
          commodityId: 'shield_emitters',
          yieldUnits: 1,
          loreId: 'lore-reach-crystal',
          scanSummary: 'Charge-rich crystal fanout, ideal for emitter tuning.',
        ),
        ResourceNode(
          id: 20002,
          sectorIndex: 1,
          name: 'PRIVATEER DEBRIS',
          kind: ResourceKind.salvage,
          position: Offset(3260, 2180),
          color: Color(0xFFFB7185),
          commodityId: 'survey_drones',
          yieldUnits: 1,
          loreId: 'lore-reach-salvage',
          scanSummary: 'Broken escort hull with survey hardware intact.',
        ),
      ],
    ),
    SectorLayout(
      name: 'Deep Survey',
      starSeed: 303,
      stations: [
        Station(
          id: 21,
          sectorIndex: 2,
          name: 'ARES I',
          position: Offset(980, 980),
          color: Color(0xFF93C5FD),
          blurb: 'Survey staging colony for deep-field crews.',
        ),
        Station(
          id: 22,
          sectorIndex: 2,
          name: 'ARES II',
          position: Offset(2020, 2320),
          color: Color(0xFF34D399),
          blurb: 'Experimental outpost with sparse resupply capacity.',
        ),
        Station(
          id: 23,
          sectorIndex: 2,
          name: 'MENDELEEV',
          position: Offset(3520, 860),
          color: Color(0xFFFBBF24),
          blurb: 'Ore convoy waypoint and long-range fuel depot.',
        ),
        Station(
          id: 24,
          sectorIndex: 2,
          name: 'SILICA',
          position: Offset(4140, 2890),
          color: Color(0xFFA78BFA),
          blurb: 'Research habitat mapping anomalous signals.',
        ),
      ],
      portals: [
        PortalGate(
          id: 3001,
          sectorIndex: 2,
          targetSectorIndex: 1,
          targetPortalId: 2002,
          name: 'Survey Return Gate',
          position: Offset(330, 3380),
          exitVector: Offset(1, -0.08),
          color: Color(0xFF22D3EE),
        ),
      ],
      resources: [
        ResourceNode(
          id: 30001,
          sectorIndex: 2,
          name: 'SURVEY RELIC',
          kind: ResourceKind.relic,
          position: Offset(2680, 1630),
          color: Color(0xFFFBBF24),
          commodityId: 'encrypted_data',
          yieldUnits: 1,
          loreId: 'lore-survey-relic',
          scanSummary: 'Sealed artifact with anomalously old telemetry.',
        ),
        ResourceNode(
          id: 30002,
          sectorIndex: 2,
          name: 'CRYO CRADLE',
          kind: ResourceKind.salvage,
          position: Offset(1320, 2560),
          color: Color(0xFF93C5FD),
          commodityId: 'cryo_foodstock',
          yieldUnits: 2,
          loreId: 'lore-survey-cradle',
          scanSummary: 'Emergency cargo shell still carrying cold stores.',
        ),
      ],
    ),
  ];

  static final List<Station> _allStations = _sectorLayouts
      .expand((layout) => layout.stations)
      .toList(growable: false);

  Station _stationById(int id) {
    for (final station in _allStations) {
      if (station.id == id) {
        return station;
      }
    }
    throw FormatException('Unknown station id $id');
  }

  Station? _stationByIdOrNull(int id) {
    for (final station in _allStations) {
      if (station.id == id) {
        return station;
      }
    }
    return null;
  }

  Station? _stationIfInCurrentSector(int id) {
    for (final station in stations) {
      if (station.id == id) {
        return station;
      }
    }
    return null;
  }

  PortalGate _portalById(int id, int sector) {
    final layout = _sectorLayouts[sector];
    for (final portal in layout.portals) {
      if (portal.id == id) {
        return portal;
      }
    }
    throw FormatException('Unknown portal $id in sector $sector');
  }
}

enum CampaignGoalType {
  dockStation,
  deliverContracts,
  killPirates,
  visitSector,
  buyUpgrades,
  crossSectorDeliveries,
}

class CampaignMission {
  const CampaignMission({
    required this.title,
    required this.description,
    required this.goalType,
    required this.target,
    required this.rewardCredits,
    this.stationId,
    this.sectorIndex,
  });

  final String title;
  final String description;
  final CampaignGoalType goalType;
  final int target;
  final int rewardCredits;
  final int? stationId;
  final int? sectorIndex;
}

enum GameAudioCue { fire, hit, dock, contract, jump, comms, warning }

class DialogueEncounter {
  const DialogueEncounter({
    required this.title,
    required this.body,
    required this.options,
  });

  final String title;
  final String body;
  final List<DialogueOption> options;
}

class DialogueOption {
  const DialogueOption({
    required this.label,
    required this.resultLog,
    this.creditsDelta = 0,
    this.fuelDelta = 0,
    this.energyDelta = 0,
    this.hullDelta = 0,
    this.shieldDelta = 0,
    this.spawnPirates = 0,
  });

  final String label;
  final String resultLog;
  final int creditsDelta;
  final double fuelDelta;
  final double energyDelta;
  final double hullDelta;
  final double shieldDelta;
  final int spawnPirates;
}

class SectorLayout {
  const SectorLayout({
    required this.name,
    required this.starSeed,
    required this.stations,
    required this.portals,
    required this.resources,
  });

  final String name;
  final int starSeed;
  final List<Station> stations;
  final List<PortalGate> portals;
  final List<ResourceNode> resources;
}

class PortalGate {
  const PortalGate({
    required this.id,
    required this.sectorIndex,
    required this.targetSectorIndex,
    required this.targetPortalId,
    required this.name,
    required this.position,
    required this.exitVector,
    required this.color,
  });

  final int id;
  final int sectorIndex;
  final int targetSectorIndex;
  final int targetPortalId;
  final String name;
  final Offset position;
  final Offset exitVector;
  final Color color;
}

class CommoditySpec {
  const CommoditySpec({
    required this.id,
    required this.name,
    required this.basePrice,
    required this.volatility,
  });

  final String id;
  final String name;
  final int basePrice;
  final double volatility;
}

class CargoContract {
  CargoContract({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.cargoUnits,
    required this.rewardCredits,
    required this.cargoName,
    this.pickedUp = false,
  });

  final int id;
  final Station pickup;
  final Station destination;
  final int cargoUnits;
  final int rewardCredits;
  final String cargoName;
  bool pickedUp;

  CargoContract copyForAcceptance() => CargoContract(
    id: id,
    pickup: pickup,
    destination: destination,
    cargoUnits: cargoUnits,
    rewardCredits: rewardCredits,
    cargoName: cargoName,
    pickedUp: pickedUp,
  );

  String statusDescription(VanSoleGame game) {
    if (!pickedUp) {
      if (game.isDocked && game.dockedStation?.id == pickup.id) {
        return 'Cargo can be loaded here (Deliver button / R).';
      }
      return 'Return to ${pickup.name} to load the cargo.';
    }
    if (game.isDocked && game.dockedStation?.id == destination.id) {
      return 'Ready to unload at destination.';
    }
    return 'En route to ${destination.name}.';
  }
}

class Station {
  const Station({
    required this.id,
    required this.sectorIndex,
    required this.name,
    required this.position,
    required this.color,
    required this.blurb,
  });

  final int id;
  final int sectorIndex;
  final String name;
  final Offset position;
  final Color color;
  final String blurb;
}

enum ResourceKind { ore, crystal, salvage, relic }

class ResourceNode {
  const ResourceNode({
    required this.id,
    required this.sectorIndex,
    required this.name,
    required this.kind,
    required this.position,
    required this.color,
    required this.commodityId,
    required this.yieldUnits,
    required this.loreId,
    required this.scanSummary,
  });

  final int id;
  final int sectorIndex;
  final String name;
  final ResourceKind kind;
  final Offset position;
  final Color color;
  final String commodityId;
  final int yieldUnits;
  final String loreId;
  final String scanSummary;
}

class LoreEntry {
  const LoreEntry({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
  });

  final String id;
  final String title;
  final String summary;
  final String body;
}

class PirateShip {
  PirateShip({
    required this.trackingId,
    required this.position,
    required this.velocity,
    required this.angle,
    required this.hull,
    required this.shield,
    required this.bias,
  });

  final int trackingId;
  Offset position;
  Offset velocity;
  double angle;
  double hull;
  double shield;
  double fireCooldown = 0;
  double bias;
}

class Projectile {
  Projectile({
    required this.position,
    required this.velocity,
    required this.ttl,
    required this.damage,
    required this.friendly,
  });

  Offset position;
  Offset velocity;
  double ttl;
  double damage;
  bool friendly;
}

class Blast {
  Blast({required this.position, required this.ttl, required this.radius});

  final Offset position;
  double ttl;
  final double radius;
}

class StarPoint {
  const StarPoint({
    required this.position,
    required this.radius,
    required this.alpha,
    required this.tint,
  });

  final Offset position;
  final double radius;
  final double alpha;
  final int tint;
}

// Renders the full flight scene: starfield, meshes, combat cues, cockpit
// overlays, and post-processing inside the fixed frame.
class Sector3DPainter extends CustomPainter {
  Sector3DPainter(this.game, {this.drawLegacyHud = true});

  final VanSoleGame game;
  final bool drawLegacyHud;
  static const double _cameraPitch = 0.29;
  static const double _nearClip = 34;
  static const double _farClip = 6800;
  static final _MeshModel _playerMesh = _buildPlayerMesh();
  static final _MeshModel _pirateMesh = _buildPirateMesh();
  static final _MeshModel _stationMeshBastion = _buildStationMeshBastion();
  static final _MeshModel _stationMeshHalo = _buildStationMeshHalo();
  static final _MeshModel _stationMeshSpire = _buildStationMeshSpire();
  static final _MeshModel _stationMeshCitadel = _buildStationMeshCitadel();
  static final _MeshModel _stationPodMesh = _buildStationPodMesh();
  static final _MeshModel _resourceCrystalMesh = _buildResourceCrystalMesh();
  static final _MeshModel _portalMesh = _buildPortalMesh();
  static final _MeshModel _projectileMesh = _buildProjectileMesh();
  static final _MeshModel _blastMesh = _buildBlastMesh();
  static final _MeshModel _characterMesh = _buildCharacterMesh();

  @override
  void paint(Canvas canvas, Size size) {
    final windowRect = Offset.zero & size;
    canvas.drawRect(windowRect, Paint()..color = const Color(0xFF000000));
    if (size.width < 180 || size.height < 110) {
      return;
    }
    final sceneSize = size;
    canvas.save();

    final rect = Offset.zero & sceneSize;
    final viewportRect = _viewportRectFor(sceneSize);
    final viewportInner = sceneSize.width <= 500
        ? _dosViewportInnerRect
        : viewportRect.deflate(drawLegacyHud ? 2 : 8);
    final center = Offset(
      viewportInner.center.dx,
      viewportInner.top + viewportInner.height * (drawLegacyHud ? 0.58 : 0.56),
    );
    final focal = viewportInner.shortestSide * (drawLegacyHud ? 1.02 : 1.22);
    final sinFacing = math.sin(game.playerFacing);
    final cosFacing = math.cos(game.playerFacing);
    final lightDir = _Vec3(
      -0.42 + math.sin(game._clock * 0.27) * 0.22,
      0.76,
      -0.52,
    ).normalized();
    canvas.drawRect(rect, Paint()..color = const Color(0xFF010205));
    canvas.drawRect(viewportInner, Paint()..color = const Color(0xFF000104));
    final speedFactor = (game.playerVelocity.distance / 360)
        .clamp(0.0, 1.0)
        .toDouble();
    _drawDeepSpaceBackdrop(
      canvas,
      viewportInner,
      speedFactor: speedFactor,
    );
    canvas.drawRect(
      viewportInner,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.25),
          radius: 1.1,
          colors: [
            const Color(0xFF0A1730).withValues(alpha: 0.22),
            Colors.transparent,
          ],
        ).createShader(viewportInner),
    );
    final dosSpriteStyle = drawLegacyHud && size.width < 220;
    final horizonCenter = viewportInner.center;
    final reticleCenter = viewportInner.center;
    _TargetSnapshot? targetSnapshot;
    final offscreenThreatDirections = <Offset>[];
    canvas.save();
    canvas.clipRect(viewportInner);

    for (final star in game.stars) {
      final dx = _wrappedDelta(
        star.position.dx - game.playerPosition.dx,
        VanSoleGame.worldWidth,
      );
      final dy = _wrappedDelta(
        star.position.dy - game.playerPosition.dy,
        VanSoleGame.worldHeight,
      );
      final right = -dx * sinFacing + dy * cosFacing;
      final forward = dx * cosFacing + dy * sinFacing;
      final projected = _project3D(
        center: center,
        focal: focal,
        right: right * 0.24,
        up: 700 + star.tint * 120,
        forward: 2600 + forward * 0.25,
      );
      if (projected == null) {
        continue;
      }
      final starColor = switch (star.tint) {
        0 => const Color(0xFFDDE9FF),
        1 => const Color(0xFFFFE7C2),
        _ => const Color(0xFFB7F6FF),
      };
      final alpha = (star.alpha * (0.55 + projected.scale * 0.25))
          .clamp(0.08, 0.95)
          .toDouble();
      canvas.drawCircle(
        projected.screen,
        (star.radius * (0.8 + projected.scale * 0.55)).clamp(0.6, 2.5),
        Paint()..color = starColor.withValues(alpha: alpha),
      );
      if (!dosSpriteStyle && speedFactor > 0.24) {
        final dir = _normalize(projected.screen - horizonCenter);
        final streakLen = (3 + speedFactor * 12 + projected.scale * 2.4).clamp(
          2.5,
          18.0,
        );
        canvas.drawLine(
          projected.screen - dir * streakLen,
          projected.screen,
          Paint()
            ..color = starColor.withValues(alpha: alpha * 0.5)
            ..strokeWidth = 1.0
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    _drawBackgroundPlanets(
      canvas,
      viewportInner,
      center: center,
      focal: focal,
      sinFacing: sinFacing,
      cosFacing: cosFacing,
    );
    _ProjectedPoint? harvestProjection;
    ResourceNode? harvestResourceNode;

    for (final resource in game.resources) {
      final view = _viewSpaceForWorld(
        resource.position,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      if (view.forward < -220) {
        continue;
      }
      final p = _project3D(
        center: center,
        focal: focal,
        right: view.right,
        up: -170,
        forward: view.forward,
      );
      if (p == null) {
        continue;
      }
      final isHarvestTarget = game.harvestCandidate?.id == resource.id;
      if (dosSpriteStyle) {
        _drawResourceNodeSprite(
          canvas,
          p.screen,
          resource: resource,
          size: (4 + p.scale * 11).clamp(4.0, 16.0).toDouble(),
          highlighted: isHarvestTarget,
        );
      } else {
        _drawResourceNodeMesh(
          canvas,
          center: center,
          focal: focal,
          resource: resource,
          origin: _Vec3(view.right, -170, view.forward),
          yaw: game._clock * 0.4 + resource.id * 0.03,
          lightDir: lightDir,
          highlighted: isHarvestTarget,
        );
      }
      if (isHarvestTarget) {
        harvestProjection = p;
        harvestResourceNode = resource;
      }
      if (drawLegacyHud && p.depth < 2400) {
        _drawLabel(
          canvas,
          p.screen + Offset(12 + p.scale * 2, 10 + p.scale * 2),
          resource.name,
          resource.color,
        );
      }
    }

    for (final station in game.stations) {
      final view = _viewSpaceForWorld(
        station.position,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      if (view.forward < -180) {
        continue;
      }
      final p = _project3D(
        center: center,
        focal: focal,
        right: view.right,
        up: -190,
        forward: view.forward,
      );
      if (p == null) {
        continue;
      }
      final fade = (1 - p.depth / _farClip).clamp(0.15, 1.0).toDouble();
      final glowRadius = (16 + p.scale * 10).clamp(10.0, 52.0).toDouble();
      final stationYaw = game._clock * 0.19 + station.id * 0.13;
      if (dosSpriteStyle) {
        _drawStationSprite(
          canvas,
          p.screen,
          station,
          size: (6 + p.scale * 22).clamp(5.0, 30.0).toDouble(),
          tracked: game.dockCandidate?.id == station.id,
        );
      } else {
        canvas.drawCircle(
          p.screen,
          glowRadius * 1.5,
          Paint()
            ..color = station.color.withValues(alpha: 0.14 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        _drawModernStationCluster(
          canvas,
          center: center,
          focal: focal,
          station: station,
          origin: _Vec3(view.right, -190, view.forward),
          yaw: stationYaw,
          lightDir: lightDir,
          tracked: game.dockCandidate?.id == station.id,
        );
      }
      _drawStationApproachLights(
        canvas,
        center: center,
        focal: focal,
        origin: _Vec3(view.right, -190, view.forward),
        yaw: stationYaw,
        color: station.color,
      );

      if (game.dockedStation?.id == station.id ||
          game.dockCandidate?.id == station.id) {
        canvas.drawCircle(
          p.screen,
          glowRadius * 1.65,
          Paint()
            ..color =
                (game.dockedStation?.id == station.id
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFFBBF24))
                    .withValues(alpha: 0.38)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      if (drawLegacyHud && p.depth < 2900) {
        _drawLabel(
          canvas,
          p.screen + Offset(16 + p.scale * 3, -20 - p.scale * 5),
          station.name,
          station.color,
        );
      }
    }

    for (final portal in game.portals) {
      final view = _viewSpaceForWorld(
        portal.position,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      if (view.forward < -220) {
        continue;
      }
      final p = _project3D(
        center: center,
        focal: focal,
        right: view.right,
        up: -150,
        forward: view.forward,
      );
      if (p == null) {
        continue;
      }
      final isJumpCandidate = game.jumpCandidate?.id == portal.id;
      final pulse = 0.62 + math.sin(game._clock * 2.2 + portal.id) * 0.2;
      final ringRadius = (16 + p.scale * 15).clamp(8.0, 58.0).toDouble();
      if (dosSpriteStyle) {
        _drawPortalSprite(
          canvas,
          p.screen,
          size: (6 + p.scale * 15).clamp(6.0, 24.0).toDouble(),
          color: portal.color,
        );
      } else {
        canvas.drawCircle(
          p.screen,
          ringRadius * 2.0,
          Paint()
            ..color = portal.color.withValues(alpha: 0.1 * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        _drawMesh(
          canvas,
          center: center,
          focal: focal,
          mesh: _portalMesh,
          origin: _Vec3(view.right, -150, view.forward),
          yaw: game._clock * 0.7 + portal.id * 0.03,
          baseColor: Color.lerp(portal.color, const Color(0xFF5C7CA2), 0.46)!,
          lightDir: lightDir,
          ambient: 0.2,
          emissiveBoost: 0.14,
          edgeAlpha: 0.2,
        );
      }
      if (isJumpCandidate) {
        canvas.drawCircle(
          p.screen,
          ringRadius * 1.95,
          Paint()
            ..color = const Color(0xFFA78BFA).withValues(alpha: 0.36)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if (drawLegacyHud && p.depth < 3200) {
        _drawLabel(
          canvas,
          p.screen + Offset(18 + p.scale * 2.5, 10 + p.scale * 3.5),
          portal.name,
          portal.color,
        );
      }
    }

    for (final blast in game.blasts) {
      final view = _viewSpaceForWorld(
        blast.position,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      if (view.forward < -180) {
        continue;
      }
      final p = _project3D(
        center: center,
        focal: focal,
        right: view.right,
        up: -170,
        forward: view.forward,
      );
      if (p == null) {
        continue;
      }
      final t = (blast.ttl / 0.45).clamp(0.0, 1.0).toDouble();
      if (dosSpriteStyle) {
        canvas.drawCircle(
          p.screen,
          (blast.radius * (1.0 - t) * p.scale).clamp(1.0, 16.0),
          Paint()
            ..isAntiAlias = false
            ..color = const Color(0xFFFFB454).withValues(alpha: 0.52 * t),
        );
        continue;
      }
      _drawMesh(
        canvas,
        center: center,
        focal: focal,
        mesh: _blastMesh,
        origin: _Vec3(view.right, -170, view.forward),
        yaw: game._clock * 1.2 + blast.radius * 0.01,
        baseColor: const Color(0xFFFFA04A),
        lightDir: lightDir,
        ambient: 0.26,
        emissiveBoost: 0.46 * t,
        edgeAlpha: 0.0,
        scale: (0.22 + blast.radius * 0.012) * (1.3 - t),
      );
      canvas.drawCircle(
        p.screen,
        (blast.radius * (1.2 - t) * p.scale).clamp(2.0, 84.0),
        Paint()
          ..color = const Color(0xFFFFB454).withValues(alpha: t * 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    if (dosSpriteStyle) {
      _drawPlayerShipSprite(
        canvas,
        reticleCenter + const Offset(0, 8),
        facing: game.playerFacing,
        pulse: 0.84 + math.sin(game._clock * 5.8) * 0.08,
      );
    } else {
      _drawPlayerShipMesh(
        canvas,
        reticleCenter + const Offset(0, 11),
        facing: game.playerFacing,
      );
    }

    for (final shot in game.projectiles) {
      final view = _viewSpaceForWorld(
        shot.position,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      if (view.forward < -160) {
        continue;
      }
      final p = _project3D(
        center: center,
        focal: focal,
        right: view.right,
        up: -170,
        forward: view.forward,
      );
      if (p == null) {
        continue;
      }
      if (dosSpriteStyle) {
        final color = shot.friendly
            ? const Color(0xFF60A5FA)
            : const Color(0xFFF87171);
        canvas.drawRect(
          Rect.fromCenter(center: p.screen, width: 2.2, height: 2.2),
          Paint()
            ..isAntiAlias = false
            ..color = color.withValues(alpha: 0.92),
        );
        continue;
      }
      final shotYaw = math.atan2(shot.velocity.dx, shot.velocity.dy);
      _drawMesh(
        canvas,
        center: center,
        focal: focal,
        mesh: _projectileMesh,
        origin: _Vec3(view.right, -170, view.forward),
        yaw: shotYaw,
        baseColor: shot.friendly
            ? const Color(0xFF8BFFE8)
            : const Color(0xFFFF8A80),
        lightDir: lightDir,
        ambient: 0.22,
        emissiveBoost: 0.9,
        edgeAlpha: 0.0,
        scale: 0.28,
      );
      final radius = (p.scale * 2.3).clamp(1.2, 5.2).toDouble();
      final tailView = _viewSpaceForWorld(
        shot.position - shot.velocity * 0.028,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      final tail = _project3D(
        center: center,
        focal: focal,
        right: tailView.right,
        up: -170,
        forward: tailView.forward,
      );
      if (tail != null) {
        canvas.drawLine(
          tail.screen,
          p.screen,
          Paint()
            ..color =
                (shot.friendly
                        ? const Color(0xFF8BFFE8)
                        : const Color(0xFFFF8A80))
                    .withValues(alpha: 0.42)
            ..strokeWidth = radius * 0.85
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(
        p.screen,
        radius,
        Paint()
          ..color = shot.friendly
              ? const Color(0xFF8BFFE8).withValues(alpha: 0.9)
              : const Color(0xFFFF8A80).withValues(alpha: 0.9),
      );
    }

    for (final pirate in game.pirates) {
      final view = _viewSpaceForWorld(
        pirate.position,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      if (view.forward < -240) {
        continue;
      }
      final p = _project3D(
        center: center,
        focal: focal,
        right: view.right,
        up: -155,
        forward: view.forward,
      );
      if (p == null) {
        continue;
      }
      final isTracked = game.trackedPirateId == pirate.trackingId;
      final distance = (pirate.position - game.playerPosition).distance;
      final isOnScreen =
          p.screen.dx >= viewportInner.left + 6 &&
          p.screen.dx <= viewportInner.right - 6 &&
          p.screen.dy >= viewportInner.top + 6 &&
          p.screen.dy <= viewportInner.bottom - 6;
      if (!isOnScreen && distance < 2200) {
        offscreenThreatDirections.add(_normalize(p.screen - reticleCenter));
      }
      final targetScore = (p.screen - reticleCenter).distance + p.depth * 0.05;
      if (isTracked ||
          (isOnScreen &&
              (targetSnapshot == null ||
                  (!targetSnapshot.isTracked &&
                      targetScore < targetSnapshot.score)))) {
        targetSnapshot = _TargetSnapshot(
          pirate: pirate,
          projection: p,
          score: targetScore,
          distance: distance,
          isTracked: isTracked,
          isOnScreen: isOnScreen,
        );
      }
      final relYaw = pirate.angle - game.playerFacing - math.pi / 2;
      if (dosSpriteStyle) {
        _drawPirateSprite(
          canvas,
          p.screen,
          size: (5 + p.scale * 15).clamp(5.0, 24.0).toDouble(),
          tracked: isTracked,
          yaw: relYaw,
        );
      } else {
        _drawMesh(
          canvas,
          center: center,
          focal: focal,
          mesh: _pirateMesh,
          origin: _Vec3(view.right, -155, view.forward),
          yaw: relYaw,
          baseColor: isTracked
              ? const Color(0xFFDCC56B)
              : const Color(0xFF5EA0E9),
          lightDir: lightDir,
          ambient: 0.24,
          emissiveBoost: 0.02,
          edgeAlpha: 0.2,
        );
      }
      if (isOnScreen) {
        final outlineRadius = (8.6 + p.scale * 7.2).clamp(7.0, 24.0);
        final outlineColor = isTracked
            ? const Color(0xFFFDE68A)
            : const Color(0xFFF87171);
        canvas.drawCircle(
          p.screen,
          outlineRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isTracked ? 1.35 : 1.0
            ..color = outlineColor.withValues(alpha: isTracked ? 0.72 : 0.52),
        );
      }

      final shieldPct = (pirate.shield / 35).clamp(0.0, 1.0).toDouble();
      if (shieldPct > 0) {
        canvas.drawCircle(
          p.screen,
          (11 + p.scale * 8).clamp(7.0, 30.0),
          Paint()
            ..color = const Color(
              0xFF93C5FD,
            ).withValues(alpha: 0.15 + shieldPct * 0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      if (isTracked) {
        final dotCenter =
            p.screen + Offset(-11 - p.scale * 2, -11 - p.scale * 2);
        canvas.drawCircle(
          dotCenter,
          (2.2 + p.scale * 0.9).clamp(2.0, 4.0),
          Paint()..color = const Color(0xFF4ADE80).withValues(alpha: 0.95),
        );
        canvas.drawCircle(
          dotCenter,
          (4.4 + p.scale * 1.4).clamp(3.2, 8.0),
          Paint()
            ..color = const Color(0xFF4ADE80).withValues(alpha: 0.26)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }

      final thruster = _projectLocalPoint(
        center: center,
        focal: focal,
        origin: _Vec3(view.right, -155, view.forward),
        yaw: relYaw,
        local: const _Vec3(0, 1.4, -24),
      );
      if (thruster != null) {
        final glow = (2.8 + p.scale * 4.4).clamp(2.0, 12.0).toDouble();
        canvas.drawCircle(
          thruster.screen,
          glow,
          Paint()
            ..color = const Color(0xFFFFAFA6).withValues(alpha: 0.38)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }

    if (game.dockCandidate != null) {
      final view = _viewSpaceForWorld(
        game.dockCandidate!.position,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      final stationScreen = _project3D(
        center: center,
        focal: focal,
        right: view.right,
        up: -190,
        forward: view.forward,
      );
      if (stationScreen != null) {
        canvas.drawLine(
          reticleCenter,
          stationScreen.screen,
          Paint()
            ..color = const Color(0xFFFBBF24).withValues(alpha: 0.46)
            ..strokeWidth = 1.6,
        );
        _drawReticle(
          canvas,
          stationScreen.screen,
          const Color(0xFFFBBF24),
          0.65 + math.sin(game._clock * 5) * 0.06,
        );
      }
      if (drawLegacyHud) {
        _drawLabel(
          canvas,
          reticleCenter + const Offset(18, 18),
          'Press E to dock',
          const Color(0xFFFBBF24),
        );
      }
    }

    if (game.jumpCandidate != null) {
      final view = _viewSpaceForWorld(
        game.jumpCandidate!.position,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      final portalScreen = _project3D(
        center: center,
        focal: focal,
        right: view.right,
        up: -150,
        forward: view.forward,
      );
      if (portalScreen != null) {
        canvas.drawLine(
          reticleCenter,
          portalScreen.screen,
          Paint()
            ..color = const Color(0xFFA78BFA).withValues(alpha: 0.42)
            ..strokeWidth = 1.4,
        );
        _drawReticle(
          canvas,
          portalScreen.screen,
          const Color(0xFFA78BFA),
          0.68 + math.sin(game._clock * 4.2) * 0.06,
        );
      }
      if (drawLegacyHud) {
        _drawLabel(
          canvas,
          reticleCenter + const Offset(18, 34),
          'Press J to jump',
          const Color(0xFFA78BFA),
        );
      }
    }

    if (harvestProjection != null && harvestResourceNode != null) {
      _drawReticle(
        canvas,
        harvestProjection.screen,
        harvestResourceNode.color,
        0.64 + math.sin(game._clock * 4.4) * 0.05,
      );
      if (drawLegacyHud) {
        _drawLabel(
          canvas,
          reticleCenter + const Offset(18, 50),
          'Press H to harvest',
          harvestResourceNode.color,
        );
      }
    }

    _drawCombatOverlays(
      canvas,
      viewportInner,
      center: center,
      focal: focal,
      sinFacing: sinFacing,
      cosFacing: cosFacing,
      reticleCenter: reticleCenter,
      target: targetSnapshot,
      offscreenThreatDirections: offscreenThreatDirections,
    );
    if (dosSpriteStyle) {
      _drawDosCrtOverlay(canvas, viewportInner);
    } else {
      _drawPostProcessing(canvas, viewportInner, speedFactor: speedFactor);
    }
    canvas.restore();
    if (game.cockpitMode == 4) {
      _drawScienceScanOverlay(canvas, viewportInner, targetSnapshot);
    }
    if (drawLegacyHud) {
      _drawCommsPrompt(canvas, viewportInner);
      _drawEncounterCockpitOverlay(canvas, sceneSize);
      _drawCockpitOverlay(canvas, sceneSize, reticleCenter);
      _drawControlPanel(
        canvas,
        sceneSize,
        target: targetSnapshot,
        reticleCenter: reticleCenter,
      );
      _drawCommandStrip(canvas, sceneSize, targetSnapshot);
    } else {
      _drawViewportReticle(canvas, reticleCenter, sceneSize.width <= 500);
      if (game.activeEncounter != null) {
        _drawEncounterCockpitOverlay(canvas, sceneSize);
      }
    }
    _drawDamageIndicator(canvas, reticleCenter);

    if (game.damageFlash > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(
            0xFFFF4D4D,
          ).withValues(alpha: game.damageFlash * 0.16),
      );
    }
    canvas.restore();
  }

  _ProjectedPoint? _project3D({
    required Offset center,
    required double focal,
    required double right,
    required double up,
    required double forward,
  }) {
    final cp = math.cos(_cameraPitch);
    final sp = math.sin(_cameraPitch);
    final y = up * cp - forward * sp;
    final z = up * sp + forward * cp;
    if (z <= _nearClip || z > _farClip) {
      return null;
    }
    final scale = focal / z;
    final x = center.dx + right * scale;
    final screenY = center.dy - y * scale;
    return _ProjectedPoint(Offset(x, screenY), z, scale);
  }

  _ProjectedPoint? _projectLocalPoint({
    required Offset center,
    required double focal,
    required _Vec3 origin,
    required double yaw,
    required _Vec3 local,
  }) {
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final rotated = _Vec3(
      local.x * cy - local.z * sy,
      local.y,
      local.x * sy + local.z * cy,
    );
    final view = origin + rotated;
    return _project3D(
      center: center,
      focal: focal,
      right: view.x,
      up: view.y,
      forward: view.z,
    );
  }

  _Vec3 _rotateLocalOffset(_Vec3 local, double yaw) {
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    return _Vec3(
      local.x * cy - local.z * sy,
      local.y,
      local.x * sy + local.z * cy,
    );
  }

  ({double right, double forward}) _viewSpaceForWorld(
    Offset world, {
    required double sinFacing,
    required double cosFacing,
  }) {
    final dx = world.dx - game.playerPosition.dx;
    final dy = world.dy - game.playerPosition.dy;
    return (
      right: -dx * sinFacing + dy * cosFacing,
      forward: dx * cosFacing + dy * sinFacing,
    );
  }

  double _wrappedDelta(double delta, double span) {
    var value = delta;
    while (value > span / 2) {
      value -= span;
    }
    while (value < -span / 2) {
      value += span;
    }
    return value;
  }

  double _panelWidthFor(Size size) {
    if (size.width <= 500) {
      return (size.width * 0.265).clamp(80.0, 92.0).toDouble();
    }
    return (size.width * 0.29).clamp(224.0, 320.0).toDouble();
  }

  Rect _viewportRectFor(Size size) {
    if (!drawLegacyHud) {
      final inset = size.width <= 500 ? 4.0 : 14.0;
      return Rect.fromLTWH(
        inset,
        inset,
        size.width - inset * 2,
        size.height - inset * 2,
      );
    }
    if (size.width <= 500) {
      return _dosViewportRect;
    }
    final panelWidth = _panelWidthFor(size);
    final left = size.width <= 500 ? 2.0 : 8.0;
    final top = size.width <= 500 ? 2.0 : 10.0;
    final rightGap = size.width <= 500 ? 4.0 : 24.0;
    final bottomGap = size.width <= 500 ? 12.0 : 30.0;
    return Rect.fromLTWH(
      left,
      top,
      size.width - panelWidth - left - rightGap,
      size.height - top - bottomGap,
    );
  }

  Rect _panelRectFor(Size size) {
    if (size.width <= 500) {
      return _dosPanelRect;
    }
    final panelWidth = _panelWidthFor(size);
    final inset = size.width <= 500 ? 2.0 : 8.0;
    final top = size.width <= 500 ? 2.0 : 8.0;
    final heightInset = size.width <= 500 ? 4.0 : 16.0;
    return Rect.fromLTWH(
      size.width - panelWidth - inset,
      top,
      panelWidth,
      size.height - heightInset,
    );
  }

  void _drawViewportReticle(Canvas canvas, Offset reticleCenter, bool compact) {
    if (compact) {
      final p = Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFF67E8F9).withValues(alpha: 0.76)
        ..strokeWidth = 1;
      canvas.drawLine(
        reticleCenter + const Offset(-5, 0),
        reticleCenter + const Offset(-2, 0),
        p,
      );
      canvas.drawLine(
        reticleCenter + const Offset(2, 0),
        reticleCenter + const Offset(5, 0),
        p,
      );
      canvas.drawLine(
        reticleCenter + const Offset(0, -5),
        reticleCenter + const Offset(0, -2),
        p,
      );
      canvas.drawLine(
        reticleCenter + const Offset(0, 2),
        reticleCenter + const Offset(0, 5),
        p,
      );
      return;
    }
    _drawReticle(
      canvas,
      reticleCenter,
      const Color(0xFF67E8F9),
      0.86 + math.sin(game._clock * 2.8) * 0.05,
    );
  }

  void _drawCockpitOverlay(Canvas canvas, Size size, Offset reticleCenter) {
    final viewportRect = _viewportRectFor(size);
    final compact = size.width <= 500;
    final framePad = compact ? 1.5 : 5.0;
    final frameOuter = Rect.fromLTWH(
      viewportRect.left - framePad,
      viewportRect.top - framePad,
      viewportRect.width + framePad * 2,
      viewportRect.height + framePad * 2,
    );
    final shellPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(frameOuter),
      Path()..addRect(viewportRect),
    );
    canvas.drawPath(
      shellPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF89909A), Color(0xFF444B56), Color(0xFF949BA5)],
          stops: [0.0, 0.52, 1.0],
        ).createShader(frameOuter),
    );
    canvas.drawRect(
      viewportRect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.02,
          colors: [
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.14),
          ],
          stops: const [0.65, 0.84, 1.0],
        ).createShader(viewportRect),
    );
    canvas.drawRect(
      frameOuter,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 0.8 : 1.4
        ..color = const Color(0xFFE5E7EB).withValues(alpha: 0.45),
    );
    canvas.drawRect(
      viewportRect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 0.7 : 1
        ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.22),
    );
    for (final corner in <Offset>[
      frameOuter.topLeft,
      frameOuter.topRight,
      frameOuter.bottomLeft,
      frameOuter.bottomRight,
    ]) {
      canvas.drawCircle(
        corner,
        compact ? 1.0 : 1.8,
        Paint()..color = const Color(0xFFE5E7EB).withValues(alpha: 0.52),
      );
    }
    if (compact) {
      final p = Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFF67E8F9).withValues(alpha: 0.72)
        ..strokeWidth = 1;
      canvas.drawLine(
        reticleCenter + const Offset(-5, 0),
        reticleCenter + const Offset(-2, 0),
        p,
      );
      canvas.drawLine(
        reticleCenter + const Offset(2, 0),
        reticleCenter + const Offset(5, 0),
        p,
      );
      canvas.drawLine(
        reticleCenter + const Offset(0, -5),
        reticleCenter + const Offset(0, -2),
        p,
      );
      canvas.drawLine(
        reticleCenter + const Offset(0, 2),
        reticleCenter + const Offset(0, 5),
        p,
      );
    } else {
      _drawReticle(
        canvas,
        reticleCenter,
        const Color(0xFF67E8F9),
        0.86 + math.sin(game._clock * 2.8) * 0.05,
      );
    }
  }

  void _drawCommandStrip(Canvas canvas, Size size, _TargetSnapshot? target) {
    final viewportRect = _viewportRectFor(size);
    final stripHeight = size.width <= 500 ? 10.0 : 16.0;
    final stripRect = Rect.fromLTWH(
      viewportRect.left,
      viewportRect.bottom + (size.width <= 500 ? 1.5 : 2.0),
      viewportRect.width,
      stripHeight,
    );
    canvas.drawRect(
      stripRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF11355C), Color(0xFF06203D)],
        ).createShader(stripRect),
    );
    canvas.drawRect(
      stripRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF8CB7DA).withValues(alpha: 0.35),
    );
    var text = '* PRESS \'C\' TO COMMUNICATE *';
    if (game.cockpitMode == 4 &&
        target == null &&
        game.nearestResource != null &&
        game.nearestResourceDistance <= 280) {
      text = 'SCIENCE SCAN OF LOCAL RESOURCE CACHE';
    } else if (game.cockpitMode == 4 && target == null) {
      text = 'OBJECT MUST BE ON SCREEN TO SCAN';
    } else if (game.cockpitMode == 4 && target != null) {
      text = 'SCIENCE SCAN OF LOCAL SPACECRAFT';
    } else if (game.harvestCandidate != null) {
      text = 'PRESS H TO HARVEST ${game.harvestCandidate!.name.toUpperCase()}';
    } else if (target != null) {
      text =
          'TARGET ${game.pirateContactName(target.pirate)}  RANGE ${_distanceKm(target.distance)}';
    } else if (game.cockpitCommsPrompt != null) {
      text = game.cockpitCommsPrompt!;
    } else if (game.commsLog.isNotEmpty) {
      text = game.commsLog.first.replaceFirst(RegExp(r'^\[[0-9:]+\]\s*'), '');
    }
    _drawHudText(
      canvas,
      Offset(stripRect.left + 4, stripRect.top + 1),
      text,
      color: const Color(0xFFE5D089),
      size: size.width <= 500 ? 5.4 : 7.4,
      weight: FontWeight.w700,
    );
    final keyText = game.harvestCandidate != null
        ? 'SPACE=STOP  ALT=FIRE  H=HARVEST  CTRL=MISSILES'
        : stripRect.width < 400
        ? 'SPACE=STOP  ALT=FIRE  CTRL=MISSILES'
        : 'SPACE=STOP  ALT=FIRE  CTRL=MISSILES  F1=MAIN MENU';
    _drawHudText(
      canvas,
      Offset(
        stripRect.left + 4,
        stripRect.top + (size.width <= 500 ? 5.0 : 9.0),
      ),
      keyText,
      color: const Color(0xFF9CC7E7),
      size: size.width <= 500 ? 4.7 : 6.6,
      weight: FontWeight.w700,
    );
  }

  void _drawReticle(Canvas canvas, Offset center, Color color, double pulse) {
    final radius = 14 * pulse;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawCircle(center, radius * 0.44, paint);
    canvas.drawLine(
      center + const Offset(-19, 0),
      center + const Offset(-5, 0),
      paint,
    );
    canvas.drawLine(
      center + const Offset(5, 0),
      center + const Offset(19, 0),
      paint,
    );
    canvas.drawLine(
      center + const Offset(0, -19),
      center + const Offset(0, -5),
      paint,
    );
    canvas.drawLine(
      center + const Offset(0, 5),
      center + const Offset(0, 19),
      paint,
    );
    canvas.drawCircle(
      center,
      1.5,
      Paint()..color = color.withValues(alpha: 0.92),
    );
  }

  void _drawDamageIndicator(Canvas canvas, Offset center) {
    if (game.incomingDamageStrength <= 0.01) {
      return;
    }
    final relative = game.incomingDamageDirection - game.playerFacing;
    final dir = Offset(math.cos(relative), math.sin(relative));
    final arcCenter = center + dir * 40;
    final start = math.atan2(dir.dy, dir.dx) - math.pi * 0.32;
    final sweep = math.pi * 0.64;
    final alpha = (0.15 + game.incomingDamageStrength * 0.75)
        .clamp(0.0, 0.92)
        .toDouble();
    final arcRect = Rect.fromCircle(
      center: arcCenter,
      radius: 34 + game.incomingDamageStrength * 10,
    );
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..color = const Color(0xFFFF6B6B).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 + game.incomingDamageStrength * 1.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      arcCenter,
      2.2 + game.incomingDamageStrength * 1.4,
      Paint()..color = const Color(0xFFFF6B6B).withValues(alpha: alpha),
    );
  }

  void _drawCommsPrompt(Canvas canvas, Rect viewportRect) {
    final prompt = game.cockpitCommsPrompt;
    if (prompt == null) {
      return;
    }
    final compact = viewportRect.width < 260;
    final hazard = prompt.contains('HAILED') || prompt.contains('MUST');
    final pulse = 0.78 + math.sin(game._clock * 5.2) * 0.14;
    final accent = hazard ? const Color(0xFFE69766) : const Color(0xFFE5D089);
    final width = math
        .min(
          viewportRect.width * (compact ? 0.96 : 0.76),
          compact ? 210.0 : 468.0,
        )
        .toDouble();
    final rect = Rect.fromCenter(
      center: Offset(
        viewportRect.center.dx,
        viewportRect.top + (compact ? 9 : 28),
      ),
      width: width,
      height: compact ? 9.5 : 20,
    );
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFF04121F).withValues(alpha: 0.95),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.32 + pulse * 0.4),
    );
    _drawHudText(
      canvas,
      Offset(rect.left + 4, rect.top + (compact ? 2 : 6)),
      prompt,
      color: accent.withValues(alpha: 0.9 + pulse * 0.08),
      size: compact ? 4.8 : 8.8,
      weight: FontWeight.w700,
    );
  }

  void _drawScienceScanOverlay(
    Canvas canvas,
    Rect viewportRect,
    _TargetSnapshot? target,
  ) {
    final compact = viewportRect.width < 260;
    final width = math
        .min(
          viewportRect.width * (compact ? 0.92 : 0.68),
          compact ? 210.0 : 360.0,
        )
        .toDouble();
    final rect = Rect.fromLTWH(
      viewportRect.left + 8,
      viewportRect.top + 10,
      width,
      compact ? 54 : 74,
    );
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFF010205).withValues(alpha: 0.86),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF8BBADE).withValues(alpha: 0.62),
    );
    if (target == null) {
      final resource = game.nearestResource;
      if (resource == null || game.nearestResourceDistance > 280) {
        return;
      }
      CommoditySpec? commodity;
      for (final entry in game.commodityCatalog) {
        if (entry.id == resource.commodityId) {
          commodity = entry;
          break;
        }
      }
      _drawHudText(
        canvas,
        Offset(rect.left + 5, rect.top + 4),
        'SCIENCE SCAN OF LOCAL RESOURCE CACHE',
        color: const Color(0xFFE5D089),
        size: compact ? 4.8 : 8.1,
        weight: FontWeight.w700,
      );
      _drawHudText(
        canvas,
        Offset(rect.left + 6, rect.top + (compact ? 13 : 18)),
        'NAME: ${resource.name}',
        color: const Color(0xFFC8D9E8),
        size: compact ? 4.6 : 8.0,
      );
      _drawHudText(
        canvas,
        Offset(rect.left + 6, rect.top + (compact ? 20 : 29)),
        'FIELD TYPE: ${resource.kind.name.toUpperCase()}',
        color: const Color(0xFFC8D9E8),
        size: compact ? 4.6 : 8.0,
      );
      _drawHudText(
        canvas,
        Offset(rect.left + 6, rect.top + (compact ? 27 : 40)),
        'RECOVERY: ${commodity?.name.toUpperCase() ?? 'UNKNOWN'}',
        color: const Color(0xFF93C5FD),
        size: compact ? 4.6 : 8.0,
      );
      _drawHudText(
        canvas,
        Offset(rect.left + 6, rect.top + (compact ? 34 : 51)),
        'YIELD: ${resource.yieldUnits} UNITS // RANGE ${_distanceKm(game.nearestResourceDistance)}',
        color: const Color(0xFFFDE68A),
        size: compact ? 4.4 : 7.6,
      );
      return;
    }
    _drawHudText(
      canvas,
      Offset(rect.left + 5, rect.top + 4),
      'SCIENCE SCAN OF LOCAL SPACECRAFT',
      color: const Color(0xFFE5D089),
      size: compact ? 4.8 : 8.1,
      weight: FontWeight.w700,
    );
    final shipName = game.pirateContactName(target.pirate);
    final shipClass = game.pirateHullClass(target.pirate);
    final shieldType = game.pirateShieldType(target.pirate);
    final cannonType = game.pirateCannonType(target.pirate);
    _drawHudText(
      canvas,
      Offset(rect.left + 6, rect.top + (compact ? 13 : 18)),
      'NAME: $shipName',
      color: const Color(0xFFC8D9E8),
      size: compact ? 4.6 : 8.0,
    );
    _drawHudText(
      canvas,
      Offset(rect.left + 6, rect.top + (compact ? 20 : 29)),
      'AREA ISSUE CLASS $shipClass',
      color: const Color(0xFFC8D9E8),
      size: compact ? 4.6 : 8.0,
    );
    _drawHudText(
      canvas,
      Offset(rect.left + 6, rect.top + (compact ? 27 : 40)),
      'SHIELD TYPE: $shieldType',
      color: const Color(0xFF93C5FD),
      size: compact ? 4.6 : 8.0,
    );
    _drawHudText(
      canvas,
      Offset(rect.left + 6, rect.top + (compact ? 34 : 51)),
      'CANNON TYPE: $cannonType',
      color: const Color(0xFFFCA5A5),
      size: compact ? 4.6 : 8.0,
    );
  }

  void _drawDeepSpaceBackdrop(
    Canvas canvas,
    Rect viewportRect, {
    required double speedFactor,
  }) {
    final palette = switch (game.sectorIndex % 4) {
      0 => (
        top: const Color(0xFF08101B),
        mid: const Color(0xFF10223B),
        glow: const Color(0xFF36B6D9),
        accent: const Color(0xFF54F0C8),
      ),
      1 => (
        top: const Color(0xFF0C1320),
        mid: const Color(0xFF1B203F),
        glow: const Color(0xFF7283FF),
        accent: const Color(0xFFFF9E6B),
      ),
      2 => (
        top: const Color(0xFF090F18),
        mid: const Color(0xFF1A2838),
        glow: const Color(0xFF44C7E8),
        accent: const Color(0xFFD7F06D),
      ),
      _ => (
        top: const Color(0xFF090E17),
        mid: const Color(0xFF221B34),
        glow: const Color(0xFF7E6BFF),
        accent: const Color(0xFF4DD6FF),
      ),
    };
    canvas.drawRect(
      viewportRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.top,
            palette.mid,
            const Color(0xFF010205),
          ],
          stops: const [0.0, 0.56, 1.0],
        ).createShader(viewportRect),
    );

    final drift = game._clock * 0.08;
    final nebulae = <({Alignment anchor, Size scale, Color color, double alpha})>[
      (
        anchor: Alignment(-0.72 + math.sin(drift) * 0.04, -0.58),
        scale: const Size(0.58, 0.42),
        color: palette.glow,
        alpha: 0.16,
      ),
      (
        anchor: Alignment(0.58, -0.18 + math.cos(drift * 1.2) * 0.05),
        scale: const Size(0.64, 0.46),
        color: palette.accent,
        alpha: 0.12,
      ),
      (
        anchor: Alignment(-0.08, 0.22 + math.sin(drift * 0.8) * 0.04),
        scale: const Size(0.72, 0.34),
        color: Color.lerp(palette.glow, palette.accent, 0.5)!,
        alpha: 0.08,
      ),
    ];
    for (final nebula in nebulae) {
      final center = Offset(
        viewportRect.left + (nebula.anchor.x + 1) * 0.5 * viewportRect.width,
        viewportRect.top + (nebula.anchor.y + 1) * 0.5 * viewportRect.height,
      );
      final nebulaRect = Rect.fromCenter(
        center: center,
        width: viewportRect.width * nebula.scale.width,
        height: viewportRect.height * nebula.scale.height,
      );
      canvas.drawOval(
        nebulaRect,
        Paint()
          ..color = nebula.color.withValues(alpha: nebula.alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 42),
      );
    }

    final dustPaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 18; i++) {
      final fx =
          (0.12 +
                  ((math.sin(i * 2.13 + game.sectorIndex) + 1) * 0.5) * 0.76 +
                  drift * 0.015 * (i.isEven ? 1 : -1)) %
              1.0;
      final fy = 0.1 + ((math.cos(i * 1.37 + game.sectorIndex * 0.4) + 1) * 0.5) * 0.8;
      final point = Offset(
        viewportRect.left + fx * viewportRect.width,
        viewportRect.top + fy * viewportRect.height,
      );
      final radius = 0.7 + (i % 3) * 0.35;
      dustPaint.color = Color.lerp(
        palette.accent,
        Colors.white,
        0.38,
      )!.withValues(alpha: 0.1 + (i % 4) * 0.025);
      canvas.drawCircle(point, radius, dustPaint);
      if (speedFactor > 0.22) {
        final streak = (4 + speedFactor * 16 + i % 5).toDouble();
        canvas.drawLine(
          point - Offset(0, streak),
          point,
          dustPaint..strokeWidth = radius,
        );
      }
    }
  }

  void _drawBackgroundPlanets(
    Canvas canvas,
    Rect viewportRect, {
    required Offset center,
    required double focal,
    required double sinFacing,
    required double cosFacing,
  }) {
    final compact = viewportRect.width < 260;
    final variants = switch (game.sectorIndex % 3) {
      0 => <({Offset position, double radius, Color ocean, Color land})>[
        (
          position: const Offset(1470, 620),
          radius: 300,
          ocean: const Color(0xFF2C67AE),
          land: const Color(0xFF5BB9C8),
        ),
        (
          position: const Offset(520, 1260),
          radius: 230,
          ocean: const Color(0xFF914A24),
          land: const Color(0xFFE5A24C),
        ),
      ],
      1 => <({Offset position, double radius, Color ocean, Color land})>[
        (
          position: const Offset(1260, 1080),
          radius: 340,
          ocean: const Color(0xFF225C97),
          land: const Color(0xFF7AD1B7),
        ),
        (
          position: const Offset(760, 520),
          radius: 210,
          ocean: const Color(0xFF725238),
          land: const Color(0xFFD8A76D),
        ),
      ],
      _ => <({Offset position, double radius, Color ocean, Color land})>[
        (
          position: const Offset(990, 490),
          radius: 320,
          ocean: const Color(0xFF1F4F88),
          land: const Color(0xFF7BC6D6),
        ),
      ],
    };
    for (final planet in variants) {
      final view = _viewSpaceForWorld(
        planet.position,
        sinFacing: sinFacing,
        cosFacing: cosFacing,
      );
      final projection = _project3D(
        center: center,
        focal: focal,
        right: view.right * 0.62,
        up: -310,
        forward: 2300 + view.forward * 0.4,
      );
      if (projection == null) {
        continue;
      }
      final radius = (planet.radius * projection.scale).clamp(10.0, 68.0);
      final planetRect = Rect.fromCircle(
        center: projection.screen,
        radius: radius,
      );
      if (!viewportRect.overlaps(planetRect.inflate(4))) {
        continue;
      }
      if (compact) {
        canvas.drawCircle(
          projection.screen,
          radius,
          Paint()
            ..isAntiAlias = false
            ..color = planet.ocean.withValues(alpha: 0.88),
        );
        canvas.drawCircle(
          projection.screen + Offset(-radius * 0.2, -radius * 0.2),
          radius * 0.35,
          Paint()
            ..isAntiAlias = false
            ..color = planet.land.withValues(alpha: 0.75),
        );
        canvas.drawCircle(
          projection.screen,
          radius,
          Paint()
            ..isAntiAlias = false
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.34),
        );
        continue;
      }
      canvas.drawCircle(
        projection.screen,
        radius * 1.3,
        Paint()
          ..color = planet.ocean.withValues(alpha: 0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        projection.screen,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            radius: 1,
            colors: [
              Color.lerp(planet.land, Colors.white, 0.16)!,
              planet.ocean,
              Color.lerp(planet.ocean, Colors.black, 0.45)!,
            ],
            stops: const [0.0, 0.58, 1.0],
          ).createShader(planetRect),
      );
      final patch = Path()
        ..addOval(
          Rect.fromCenter(
            center: projection.screen + Offset(radius * 0.12, -radius * 0.06),
            width: radius * 1.02,
            height: radius * 0.54,
          ),
        )
        ..addOval(
          Rect.fromCenter(
            center: projection.screen + Offset(-radius * 0.22, radius * 0.18),
            width: radius * 0.62,
            height: radius * 0.34,
          ),
        );
      canvas.drawPath(
        patch,
        Paint()..color = planet.land.withValues(alpha: 0.28),
      );
      canvas.drawCircle(
        projection.screen,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.3),
      );
    }
  }

  void _drawPlayerShipSprite(
    Canvas canvas,
    Offset center, {
    required double facing,
    required double pulse,
  }) {
    final bodyColor = const Color(0xFFDDE5EE);
    final edge = Paint()
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFBFC7D2);
    final fill = Paint()
      ..isAntiAlias = false
      ..style = PaintingStyle.fill
      ..color = bodyColor;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(facing - math.pi / 2);
    final hull = Path()
      ..moveTo(0, -9)
      ..lineTo(5, 2)
      ..lineTo(2, 4)
      ..lineTo(0, 2)
      ..lineTo(-2, 4)
      ..lineTo(-5, 2)
      ..close();
    canvas.drawPath(hull, fill);
    canvas.drawPath(hull, edge);
    final wing = Path()
      ..moveTo(-8, 1)
      ..lineTo(-3, 2)
      ..lineTo(-3, 4)
      ..lineTo(-8, 3)
      ..close();
    canvas.drawPath(wing, fill);
    canvas.drawPath(wing, edge);
    final wing2 = Path()
      ..moveTo(8, 1)
      ..lineTo(3, 2)
      ..lineTo(3, 4)
      ..lineTo(8, 3)
      ..close();
    canvas.drawPath(wing2, fill);
    canvas.drawPath(wing2, edge);
    final flameAlpha = (0.38 + pulse * 0.4).clamp(0.0, 0.92).toDouble();
    canvas.drawCircle(
      const Offset(0, 6),
      1.3,
      Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFFFFA34D).withValues(alpha: flameAlpha),
    );
    canvas.restore();
  }

  void _drawPlayerShipMesh(
    Canvas canvas,
    Offset center, {
    required double facing,
  }) {
    const focal = 108.0;
    final yaw = facing - math.pi / 2;
    final origin = const _Vec3(0, -10, 162);
    final lightDir = _Vec3(-0.42, 0.82, -0.36).normalized();
    _drawMesh(
      canvas,
      center: center,
      focal: focal,
      mesh: _playerMesh,
      origin: origin,
      yaw: yaw,
      baseColor: const Color(0xFFD8E0E8),
      lightDir: lightDir,
      ambient: 0.28,
      emissiveBoost: 0.05,
      edgeAlpha: 0.24,
      scale: 1.18,
    );

    for (final local in const <_Vec3>[
      _Vec3(-9, -1.5, -26),
      _Vec3(9, -1.5, -26),
    ]) {
      final thruster = _projectLocalPoint(
        center: center,
        focal: focal,
        origin: origin,
        yaw: yaw,
        local: local,
      );
      if (thruster == null) {
        continue;
      }
      canvas.drawLine(
        thruster.screen + const Offset(0, 4),
        thruster.screen + const Offset(0, 28),
        Paint()
          ..color = const Color(0xFFFFA04A).withValues(alpha: 0.16)
          ..strokeWidth = (2.2 + thruster.scale * 1.4).clamp(1.8, 4.2)
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        thruster.screen,
        (3.2 + thruster.scale * 3.8).clamp(2.4, 7.8),
        Paint()
          ..color = const Color(0xFFFFA04A).withValues(alpha: 0.34)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        thruster.screen,
        (1.2 + thruster.scale * 1.1).clamp(1.0, 2.6),
        Paint()..color = const Color(0xFFFFD38B).withValues(alpha: 0.95),
      );
    }
  }

  void _drawPirateSprite(
    Canvas canvas,
    Offset center, {
    required double size,
    required bool tracked,
    required double yaw,
  }) {
    final scale = size / 10;
    final body = Path()
      ..moveTo(0, -9)
      ..lineTo(6, -1)
      ..lineTo(5, 2)
      ..lineTo(2, 3)
      ..lineTo(0, 1)
      ..lineTo(-2, 3)
      ..lineTo(-5, 2)
      ..lineTo(-6, -1)
      ..close();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(yaw);
    canvas.scale(scale, scale);
    final fillColor = tracked
        ? const Color(0xFFF3E39B)
        : const Color(0xFFE9EDF1);
    canvas.drawPath(
      body,
      Paint()
        ..isAntiAlias = false
        ..style = PaintingStyle.fill
        ..color = fillColor,
    );
    canvas.drawPath(
      body,
      Paint()
        ..isAntiAlias = false
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFBF4545),
    );
    canvas.drawLine(
      const Offset(-8, 1),
      const Offset(8, 1),
      Paint()
        ..isAntiAlias = false
        ..strokeWidth = 1
        ..color = const Color(0xFFBF4545).withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  void _drawStationSprite(
    Canvas canvas,
    Offset center,
    Station station, {
    required double size,
    required bool tracked,
  }) {
    final scale = size / 12;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale);
    final hull = Path()
      ..moveTo(-11, -4)
      ..lineTo(-4, -9)
      ..lineTo(5, -7)
      ..lineTo(12, -1)
      ..lineTo(9, 6)
      ..lineTo(2, 10)
      ..lineTo(-8, 8)
      ..close();
    canvas.drawPath(
      hull,
      Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFF7E603A),
    );
    canvas.drawPath(
      hull,
      Paint()
        ..isAntiAlias = false
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFA37B4B),
    );
    canvas.drawCircle(
      const Offset(-2, 1),
      2.2,
      Paint()
        ..isAntiAlias = false
        ..color = station.color.withValues(alpha: 0.72),
    );
    canvas.drawRect(
      Rect.fromLTWH(4, 0, 4, 2.5),
      Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFFC5CBD4).withValues(alpha: 0.7),
    );
    if (tracked) {
      canvas.drawRect(
        Rect.fromCenter(center: const Offset(0, 0), width: 26, height: 20),
        Paint()
          ..isAntiAlias = false
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFFBBF24),
      );
    }
    canvas.restore();
  }

  void _drawPortalSprite(
    Canvas canvas,
    Offset center, {
    required double size,
    required Color color,
  }) {
    final r = size.clamp(6.0, 28.0);
    final rect = Rect.fromCircle(center: center, radius: r);
    final inner = Rect.fromCircle(center: center, radius: r * 0.58);
    canvas.drawRect(
      rect,
      Paint()
        ..isAntiAlias = false
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.85),
    );
    canvas.drawRect(
      inner,
      Paint()
        ..isAntiAlias = false
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFAEC5DD).withValues(alpha: 0.5),
    );
  }

  void _drawResourceNodeSprite(
    Canvas canvas,
    Offset center, {
    required ResourceNode resource,
    required double size,
    required bool highlighted,
  }) {
    final radius = size.clamp(3.0, 14.0);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..isAntiAlias = false
        ..color = resource.color.withValues(alpha: 0.8),
    );
    canvas.drawCircle(
      center + Offset(-radius * 0.22, -radius * 0.22),
      radius * 0.34,
      Paint()
        ..isAntiAlias = false
        ..color = Colors.white.withValues(alpha: 0.52),
    );
    if (highlighted) {
      canvas.drawCircle(
        center,
        radius * 1.5,
        Paint()
          ..isAntiAlias = false
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = resource.color.withValues(alpha: 0.88),
      );
    }
  }

  void _drawResourceNodeMesh(
    Canvas canvas, {
    required Offset center,
    required double focal,
    required ResourceNode resource,
    required _Vec3 origin,
    required double yaw,
    required _Vec3 lightDir,
    required bool highlighted,
  }) {
    final mesh = resource.kind == ResourceKind.salvage
        ? _stationPodMesh
        : _resourceCrystalMesh;
    final baseColor = switch (resource.kind) {
      ResourceKind.ore => const Color(0xFF775438),
      ResourceKind.crystal => resource.color,
      ResourceKind.salvage => const Color(0xFF8DA1B7),
      ResourceKind.relic => const Color(0xFFC79835),
    };
    final scale = switch (resource.kind) {
      ResourceKind.ore => 0.18,
      ResourceKind.crystal => 0.24,
      ResourceKind.salvage => 0.16,
      ResourceKind.relic => 0.2,
    };
    _drawMesh(
      canvas,
      center: center,
      focal: focal,
      mesh: mesh,
      origin: origin,
      yaw: yaw,
      baseColor: baseColor,
      lightDir: lightDir,
      ambient: 0.24,
      emissiveBoost: resource.kind == ResourceKind.crystal ? 0.1 : 0.04,
      edgeAlpha: 0.2,
      scale: highlighted ? scale * 1.08 : scale,
    );
    if (!highlighted) {
      return;
    }
    final projection = _project3D(
      center: center,
      focal: focal,
      right: origin.x,
      up: origin.y,
      forward: origin.z,
    );
    if (projection == null) {
      return;
    }
    canvas.drawCircle(
      projection.screen,
      (14 + projection.scale * 10).clamp(10.0, 24.0),
      Paint()
        ..color = resource.color.withValues(
          alpha: 0.18 + 0.08 * math.sin(game._clock * 4.8),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _drawModernStationCluster(
    Canvas canvas, {
    required Offset center,
    required double focal,
    required Station station,
    required _Vec3 origin,
    required double yaw,
    required _Vec3 lightDir,
    required bool tracked,
  }) {
    final coreMesh = _stationMeshFor(station);
    final coreColor = Color.lerp(
      const Color(0xFF7B5936),
      const Color(0xFF9D7044),
      (station.id % 3) / 2,
    )!;
    final podColor = Color.lerp(
      const Color(0xFF8E9CA8),
      const Color(0xFFB5C3CF),
      (station.id % 4) / 3,
    )!;
    final glowColor = Color.lerp(station.color, const Color(0xFF8DE5D8), 0.42)!;

    _drawMesh(
      canvas,
      center: center,
      focal: focal,
      mesh: coreMesh,
      origin: origin,
      yaw: yaw,
      baseColor: coreColor,
      lightDir: lightDir,
      ambient: 0.22,
      emissiveBoost: 0.06,
      edgeAlpha: 0.24,
      scale: tracked ? 0.58 : 0.5,
    );

    for (final side in const <double>[-1, 1]) {
      final podOrigin =
          origin + _rotateLocalOffset(_Vec3(30 * side, 3, -3), yaw);
      _drawMesh(
        canvas,
        center: center,
        focal: focal,
        mesh: _stationPodMesh,
        origin: podOrigin,
        yaw: yaw + math.pi / 2,
        baseColor: podColor,
        lightDir: lightDir,
        ambient: 0.28,
        emissiveBoost: 0.04,
        edgeAlpha: 0.18,
        scale: 0.22,
      );

      final tankOrigin =
          origin + _rotateLocalOffset(_Vec3(16 * side, 6, 5), yaw);
      _drawMesh(
        canvas,
        center: center,
        focal: focal,
        mesh: _stationPodMesh,
        origin: tankOrigin,
        yaw: yaw + math.pi / 2,
        baseColor: glowColor,
        lightDir: lightDir,
        ambient: 0.3,
        emissiveBoost: 0.08,
        edgeAlpha: 0.16,
        scale: 0.12,
      );

      for (final z in const <double>[-12, 10, 32]) {
        final light = _projectLocalPoint(
          center: center,
          focal: focal,
          origin: origin,
          yaw: yaw,
          local: _Vec3(36 * side, 2, z * 0.55),
        );
        if (light == null) {
          continue;
        }
        canvas.drawCircle(
          light.screen,
          (1.3 + light.scale * 1.2).clamp(1.1, 2.8),
          Paint()..color = const Color(0xFFFFB454).withValues(alpha: 0.82),
        );
      }
    }
  }

  void _drawEncounterCockpitOverlay(Canvas canvas, Size size) {
    final encounter = game.activeEncounter;
    if (encounter == null) {
      return;
    }
    final viewportRect = _viewportRectFor(
      size,
    ).deflate(size.width <= 500 ? 1.5 : 6);
    if (viewportRect.width < 330 || viewportRect.height < 210) {
      if (size.width > 500) {
        return;
      }
    }

    final cardWidth = math
        .min(
          viewportRect.width * (size.width <= 500 ? 0.96 : 0.88),
          size.width <= 500 ? 220.0 : 560.0,
        )
        .toDouble();
    final cardHeight = math
        .min(
          viewportRect.height * (size.width <= 500 ? 0.62 : 0.58),
          size.width <= 500 ? 112.0 : 286.0,
        )
        .toDouble();
    final cardRect = Rect.fromCenter(
      center: Offset(
        viewportRect.center.dx,
        viewportRect.bottom - cardHeight * (size.width <= 500 ? 0.54 : 0.58),
      ),
      width: cardWidth,
      height: cardHeight,
    );
    final pulse = 0.68 + 0.32 * math.sin(game._clock * 5.4);
    final shadowRect = cardRect.inflate(4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shadowRect, const Radius.circular(8)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.34)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cardRect, const Radius.circular(6)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF061224), Color(0xFF060E1A), Color(0xFF081427)],
          stops: [0.0, 0.56, 1.0],
        ).createShader(cardRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cardRect, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = const Color(0xFF8CC5E9).withValues(alpha: 0.52),
    );

    final headerRect = Rect.fromLTWH(
      cardRect.left + 1,
      cardRect.top + 1,
      cardRect.width - 2,
      18,
    );
    canvas.drawRect(headerRect, Paint()..color = const Color(0xFF0A325A));
    canvas.drawRect(
      headerRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF8AC7ED).withValues(alpha: 0.66),
    );
    _drawHudText(
      canvas,
      Offset(headerRect.left + 6, headerRect.top + 4),
      'COMMUNICATION // ${_encounterCallerTitle(encounter)}',
      color: const Color(0xFFE5D089),
      size: size.width <= 500 ? 5.4 : 8.3,
      weight: FontWeight.w700,
    );

    final inner = cardRect.deflate(8);
    final portraitsTop = headerRect.bottom + 8;
    final portraitWidth = math.min(
      size.width <= 500 ? 38.0 : 80.0,
      inner.width * 0.2,
    );
    final portraitHeight = math.min(
      size.width <= 500 ? 34.0 : 74.0,
      inner.height * 0.34,
    );
    final pilotRect = Rect.fromLTWH(
      inner.left,
      portraitsTop,
      portraitWidth,
      portraitHeight,
    );
    final callerRect = Rect.fromLTWH(
      inner.right - portraitWidth,
      portraitsTop,
      portraitWidth,
      portraitHeight,
    );
    final messageRect = Rect.fromLTWH(
      pilotRect.right + 8,
      portraitsTop,
      inner.width - portraitWidth * 2 - 16,
      portraitHeight + 22,
    );
    _drawCommsPortrait(
      canvas,
      pilotRect,
      label: 'YOU',
      accent: const Color(0xFF67E8F9),
      hostile: false,
    );
    _drawCommsPortrait(
      canvas,
      callerRect,
      label: _encounterPortraitTag(encounter),
      accent: const Color(0xFFE5D089),
      hostile: true,
    );
    _drawHudText(
      canvas,
      Offset(messageRect.left, messageRect.top),
      'INCOMING HAIL',
      color: const Color(0xFF9EDBFF),
      size: size.width <= 500 ? 5.2 : 8.2,
      weight: FontWeight.w700,
    );
    _drawHudParagraph(
      canvas,
      Rect.fromLTWH(
        messageRect.left,
        messageRect.top + 11,
        messageRect.width,
        messageRect.height - 11,
      ),
      encounter.body,
      color: const Color(0xFFC8D9E8),
      size: size.width <= 500 ? 5.0 : 8.4,
      maxLines: size.width <= 500 ? 3 : 4,
    );

    final optionsTop = portraitsTop + portraitHeight + 10;
    final optionsRect = Rect.fromLTWH(
      inner.left,
      optionsTop,
      inner.width,
      inner.bottom - optionsTop,
    );
    _drawHudText(
      canvas,
      Offset(
        optionsRect.left + 1,
        optionsRect.top - (size.width <= 500 ? 5 : 10),
      ),
      'SELECT A RESPONSE',
      color: const Color(0xFFE5D089),
      size: size.width <= 500 ? 4.9 : 7.8,
      weight: FontWeight.w700,
    );
    final rowCount = encounter.options.length.clamp(1, 3);
    final compact = size.width <= 500;
    final rowHeight = compact
        ? ((optionsRect.height - 6) / rowCount).clamp(6.5, 10.5).toDouble()
        : ((optionsRect.height - 16) / rowCount).clamp(18.0, 28.0).toDouble();
    for (var i = 0; i < rowCount; i++) {
      final rowRect = Rect.fromLTWH(
        optionsRect.left,
        optionsRect.top + i * rowHeight,
        optionsRect.width,
        compact ? rowHeight - 0.6 : rowHeight - 1.5,
      );
      final alpha = i == 0 ? 0.26 + pulse * 0.14 : 0.16;
      canvas.drawRect(
        rowRect,
        Paint()
          ..color = (i == 0 ? const Color(0xFF1C3E5A) : const Color(0xFF091322))
              .withValues(alpha: alpha),
      );
      canvas.drawRect(
        rowRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = (i == 0 ? const Color(0xFFE5D089) : const Color(0xFF7BA9CA))
              .withValues(alpha: i == 0 ? 0.72 : 0.34),
      );
      _drawHudText(
        canvas,
        Offset(rowRect.left + 5, rowRect.top + 5),
        '${i + 1}. ${encounter.options[i].label.toUpperCase()}',
        color: i == 0 ? const Color(0xFFFDE68A) : const Color(0xFFD2E4F4),
        size: size.width <= 500 ? 4.7 : 8.0,
        weight: FontWeight.w700,
      );
    }
    _drawHudText(
      canvas,
      Offset(
        optionsRect.left + 1,
        optionsRect.bottom - (size.width <= 500 ? 5 : 10),
      ),
      'PRESS 1-${encounter.options.length} TO RESPOND',
      color: const Color(0xFF9EDBFF).withValues(alpha: 0.86 + pulse * 0.12),
      size: size.width <= 500 ? 4.8 : 7.8,
      weight: FontWeight.w700,
    );
  }

  void _drawCommsPortrait(
    Canvas canvas,
    Rect rect, {
    required String label,
    required Color accent,
    required bool hostile,
  }) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFF040C18));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.6),
    );
    canvas.drawRect(
      rect.deflate(1),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.18),
          radius: 1.0,
          colors: [
            accent.withValues(alpha: hostile ? 0.2 : 0.15),
            Colors.transparent,
          ],
        ).createShader(rect.deflate(1)),
    );

    final center = Offset(rect.center.dx, rect.top + rect.height * 0.5);
    _drawMesh(
      canvas,
      center: center + Offset(0, rect.height * 0.03),
      focal: rect.width * 0.78,
      mesh: _characterMesh,
      origin: const _Vec3(0, -1, 46),
      yaw: hostile ? 0.22 : -0.18,
      baseColor: hostile ? const Color(0xFFB97749) : const Color(0xFF5E88C6),
      lightDir: _Vec3(-0.35, 0.82, -0.28).normalized(),
      ambient: 0.3,
      emissiveBoost: hostile ? 0.02 : 0.04,
      edgeAlpha: 0.12,
      scale: rect.height <= 40 ? 0.88 : 1.06,
    );

    final shoulder = Path()
      ..moveTo(rect.left + 8, rect.bottom - 12)
      ..quadraticBezierTo(
        center.dx,
        rect.bottom - (hostile ? 30 : 24),
        rect.right - 8,
        rect.bottom - 12,
      )
      ..lineTo(rect.right - 8, rect.bottom - 3)
      ..lineTo(rect.left + 8, rect.bottom - 3)
      ..close();
    canvas.drawPath(
      shoulder,
      Paint()..color = accent.withValues(alpha: hostile ? 0.36 : 0.26),
    );
    canvas.drawCircle(
      center + const Offset(0, -7),
      rect.height * 0.18,
      Paint()..color = accent.withValues(alpha: hostile ? 0.52 : 0.36),
    );
    final visorRect = Rect.fromCenter(
      center: center + const Offset(0, -8),
      width: rect.width * 0.42,
      height: rect.height * 0.14,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(visorRect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF031422).withValues(alpha: 0.9),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(visorRect, const Radius.circular(2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = accent.withValues(alpha: 0.85),
    );
    _drawHudText(
      canvas,
      Offset(rect.left + 2, rect.bottom - (rect.height <= 40 ? 5.2 : 9)),
      label,
      color: accent.withValues(alpha: 0.95),
      size: rect.height <= 40 ? 4.2 : 6.8,
      weight: FontWeight.w700,
    );
  }

  void _drawHudParagraph(
    Canvas canvas,
    Rect bounds,
    String text, {
    required Color color,
    required double size,
    int? maxLines,
    FontWeight weight = FontWeight.w600,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: 0.34,
          height: 1.06,
          fontFamilyFallback: const ['Menlo', 'Monaco', 'Courier New'],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: bounds.width);
    painter.paint(canvas, Offset(bounds.left, bounds.top));
  }

  String _encounterCallerTitle(DialogueEncounter encounter) {
    final title = encounter.title.toUpperCase();
    if (title.contains('DISTRESS')) {
      return 'DISTRESS RELAY';
    }
    if (title.contains('TRADER')) {
      return 'FREE TRADER';
    }
    if (title.contains('PATROL')) {
      return 'REGIONAL PATROL';
    }
    if (title.contains('SALVAGE')) {
      return 'SALVAGE DRIFT';
    }
    return 'UNKNOWN CONTACT';
  }

  String _encounterPortraitTag(DialogueEncounter encounter) {
    final title = encounter.title.toUpperCase();
    if (title.contains('DISTRESS')) {
      return 'MAYDAY';
    }
    if (title.contains('TRADER')) {
      return 'TRADER';
    }
    if (title.contains('PATROL')) {
      return 'PATROL';
    }
    if (title.contains('SALVAGE')) {
      return 'SALVAGE';
    }
    return 'UNKNOWN';
  }

  void _drawStationApproachLights(
    Canvas canvas, {
    required Offset center,
    required double focal,
    required _Vec3 origin,
    required double yaw,
    required Color color,
  }) {
    final pulse = 0.5 + 0.5 * math.sin(game._clock * 3.8 + origin.z * 0.002);
    for (var i = 0; i < 4; i++) {
      final z = 54 + i * 12.0;
      final left = _projectLocalPoint(
        center: center,
        focal: focal,
        origin: origin,
        yaw: yaw,
        local: _Vec3(-9, 1.6, z),
      );
      final right = _projectLocalPoint(
        center: center,
        focal: focal,
        origin: origin,
        yaw: yaw,
        local: _Vec3(9, 1.6, z),
      );
      if (left != null) {
        final r = (1.4 + left.scale * 0.9).clamp(1.2, 3.4).toDouble();
        canvas.drawCircle(
          left.screen,
          r,
          Paint()..color = color.withValues(alpha: 0.28 + pulse * 0.42),
        );
      }
      if (right != null) {
        final r = (1.4 + right.scale * 0.9).clamp(1.2, 3.4).toDouble();
        canvas.drawCircle(
          right.screen,
          r,
          Paint()..color = color.withValues(alpha: 0.28 + pulse * 0.42),
        );
      }
    }
  }

  _MeshModel _stationMeshFor(Station station) {
    final name = station.name.toUpperCase();
    if (name == 'HOLIA' || name == 'REDLIC') {
      return _stationMeshCitadel;
    }
    return switch (station.id % 4) {
      0 => _stationMeshSpire,
      1 => _stationMeshBastion,
      2 => _stationMeshHalo,
      _ => _stationMeshCitadel,
    };
  }

  void _drawCombatOverlays(
    Canvas canvas,
    Rect viewportRect, {
    required Offset center,
    required double focal,
    required double sinFacing,
    required double cosFacing,
    required Offset reticleCenter,
    required _TargetSnapshot? target,
    required List<Offset> offscreenThreatDirections,
  }) {
    _drawReticleThreatRing(canvas, reticleCenter);
    if (target != null) {
      final targetName = game.pirateContactName(target.pirate);
      if (target.isOnScreen) {
        _drawTargetBracket(
          canvas,
          target.projection.screen,
          const Color(0xFFE5D089),
          11 + target.projection.scale * 6,
        );
        final lockAlpha =
            (1 - (target.projection.screen - reticleCenter).distance / 240)
                .clamp(0.22, 0.92)
                .toDouble();
        canvas.drawLine(
          reticleCenter,
          target.projection.screen,
          Paint()
            ..color = const Color(
              0xFFE5D089,
            ).withValues(alpha: lockAlpha * 0.26)
            ..strokeWidth = 1.0,
        );
        final leadWorld =
            target.pirate.position + target.pirate.velocity * 0.34;
        final leadView = _viewSpaceForWorld(
          leadWorld,
          sinFacing: sinFacing,
          cosFacing: cosFacing,
        );
        final lead = _project3D(
          center: center,
          focal: focal,
          right: leadView.right,
          up: -155,
          forward: leadView.forward,
        );
        if (lead != null) {
          final markerSize = (5 + target.projection.scale * 3.4).clamp(
            4.0,
            12.0,
          );
          final diamond = Path()
            ..moveTo(lead.screen.dx, lead.screen.dy - markerSize)
            ..lineTo(lead.screen.dx + markerSize, lead.screen.dy)
            ..lineTo(lead.screen.dx, lead.screen.dy + markerSize)
            ..lineTo(lead.screen.dx - markerSize, lead.screen.dy)
            ..close();
          canvas.drawPath(
            diamond,
            Paint()
              ..color = const Color(0xFFE5D089).withValues(alpha: 0.14)
              ..style = PaintingStyle.fill,
          );
          canvas.drawPath(
            diamond,
            Paint()
              ..color = const Color(0xFFE5D089).withValues(alpha: 0.74)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0,
          );
          canvas.drawLine(
            target.projection.screen,
            lead.screen,
            Paint()
              ..color = const Color(0xFFE5D089).withValues(alpha: 0.22)
              ..strokeWidth = 0.9,
          );
        }
      } else {
        var dir = _normalize(target.projection.screen - reticleCenter);
        if (dir == Offset.zero) {
          final view = _viewSpaceForWorld(
            target.pirate.position,
            sinFacing: sinFacing,
            cosFacing: cosFacing,
          );
          dir = _normalize(Offset(view.right, -view.forward));
        }
        _drawTrackedEdgeCue(
          canvas,
          viewportRect,
          direction: dir,
          label: targetName,
        );
        _drawHudText(
          canvas,
          reticleCenter + const Offset(-74, 46),
          'TARGET OFF-SCREEN',
          color: const Color(0xFFFBBF24),
          size: 9.6,
          weight: FontWeight.w700,
        );
      }
    }

    final uniqueDirections = <Offset>[];
    for (final dir in offscreenThreatDirections) {
      if (dir == Offset.zero) {
        continue;
      }
      final similar = uniqueDirections.any(
        (known) => (known - dir).distance < 0.28,
      );
      if (similar) {
        continue;
      }
      uniqueDirections.add(dir);
      if (uniqueDirections.length >= 4) {
        break;
      }
    }
    for (var i = 0; i < uniqueDirections.length; i++) {
      _drawThreatArrow(
        canvas,
        viewportRect,
        uniqueDirections[i],
        0.65 + (1 - i / uniqueDirections.length) * 0.25,
      );
    }
  }

  void _drawReticleThreatRing(Canvas canvas, Offset reticleCenter) {
    if (!game.nearestPirateDistance.isFinite) {
      return;
    }
    final intensity = (1 - game.nearestPirateDistance / 760)
        .clamp(0.0, 1.0)
        .toDouble();
    if (intensity <= 0.18) {
      return;
    }
    final pulse = 0.7 + 0.3 * math.sin(game._clock * 6.0);
    final color = const Color(0xFFE5D089);
    canvas.drawCircle(
      reticleCenter,
      22 + intensity * 10,
      Paint()
        ..color = color.withValues(alpha: (0.08 + intensity * 0.16) * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9 + intensity * 0.6,
    );
  }

  void _drawTargetBracket(
    Canvas canvas,
    Offset center,
    Color color,
    double radius,
  ) {
    final r = radius.clamp(14.0, 42.0).toDouble();
    final paint = Paint()
      ..color = color.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      center + Offset(-r, -r),
      center + Offset(-r * 0.45, -r),
      paint,
    );
    canvas.drawLine(
      center + Offset(-r, -r),
      center + Offset(-r, -r * 0.45),
      paint,
    );
    canvas.drawLine(
      center + Offset(r, -r),
      center + Offset(r * 0.45, -r),
      paint,
    );
    canvas.drawLine(
      center + Offset(r, -r),
      center + Offset(r, -r * 0.45),
      paint,
    );
    canvas.drawLine(
      center + Offset(-r, r),
      center + Offset(-r * 0.45, r),
      paint,
    );
    canvas.drawLine(
      center + Offset(-r, r),
      center + Offset(-r, r * 0.45),
      paint,
    );
    canvas.drawLine(center + Offset(r, r), center + Offset(r * 0.45, r), paint);
    canvas.drawLine(center + Offset(r, r), center + Offset(r, r * 0.45), paint);
  }

  void _drawThreatArrow(
    Canvas canvas,
    Rect bounds,
    Offset direction,
    double alpha,
  ) {
    final dir = _normalize(direction);
    if (dir == Offset.zero) {
      return;
    }
    final center = Offset(bounds.center.dx, bounds.center.dy + 8);
    final raw = center + dir * 1200;
    const margin = 28.0;
    final mx = math.min(margin, bounds.width * 0.45);
    final my = math.min(margin, bounds.height * 0.45);
    final tip = Offset(
      raw.dx.clamp(bounds.left + mx, bounds.right - mx).toDouble(),
      raw.dy.clamp(bounds.top + my, bounds.bottom - my).toDouble(),
    );
    final tangent = Offset(-dir.dy, dir.dx);
    final base = tip - dir * 18;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + tangent.dx * 8, base.dy + tangent.dy * 8)
      ..lineTo(base.dx - tangent.dx * 8, base.dy - tangent.dy * 8)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFF87171).withValues(alpha: alpha * 0.28)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFF87171).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _drawTrackedEdgeCue(
    Canvas canvas,
    Rect bounds, {
    required Offset direction,
    required String label,
  }) {
    final dir = _normalize(direction);
    if (dir == Offset.zero) {
      return;
    }
    final center = Offset(bounds.center.dx, bounds.center.dy + 12);
    final raw = center + dir * 1200;
    const margin = 34.0;
    final mx = math.min(margin, bounds.width * 0.45);
    final my = math.min(margin, bounds.height * 0.45);
    final tip = Offset(
      raw.dx.clamp(bounds.left + mx, bounds.right - mx).toDouble(),
      raw.dy.clamp(bounds.top + my, bounds.bottom - my).toDouble(),
    );
    final tangent = Offset(-dir.dy, dir.dx);
    final inner = tip - dir * 26;
    final cue = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(inner.dx + tangent.dx * 10, inner.dy + tangent.dy * 10)
      ..lineTo(inner.dx - tangent.dx * 10, inner.dy - tangent.dy * 10)
      ..close();
    final pulse = 0.6 + 0.4 * math.sin(game._clock * 7.6);
    canvas.drawPath(
      cue,
      Paint()
        ..color = const Color(0xFF4ADE80).withValues(alpha: 0.2 + pulse * 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      cue,
      Paint()
        ..color = const Color(0xFF4ADE80).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    final textPos = tip + tangent * 12 - dir * 14;
    _drawHudText(
      canvas,
      textPos,
      label,
      color: const Color(0xFF86EFAC),
      size: 9.1,
      weight: FontWeight.w700,
    );
  }

  void _drawControlPanel(
    Canvas canvas,
    Size size, {
    required _TargetSnapshot? target,
    required Offset reticleCenter,
  }) {
    if (size.width < 280 || size.height < 160) {
      return;
    }
    if (size.width <= 500 || size.height <= 300) {
      _drawControlPanelDosCompact(
        canvas,
        size,
        target: target,
        reticleCenter: reticleCenter,
      );
      return;
    }
    const steelTop = Color(0xFF8E949F);
    const steelMid = Color(0xFF474F5A);
    const steelBottom = Color(0xFF9CA3AD);
    const panelBlue = Color(0xFF7BB7DF);
    const panelAmber = Color(0xFFE5D089);
    const panelText = Color(0xFFC6D6E4);
    const panelWarning = Color(0xFFFCA5A5);
    final panelWidth = (size.width * 0.29).clamp(224.0, 320.0).toDouble();
    final panelRect = Rect.fromLTWH(
      size.width - panelWidth - 8,
      8,
      panelWidth,
      size.height - 16,
    );
    canvas.drawRect(
      panelRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [steelTop, steelMid, steelBottom],
          stops: [0.0, 0.52, 1.0],
        ).createShader(panelRect),
    );
    final body = panelRect.deflate(3);
    canvas.drawRect(body, Paint()..color = const Color(0xFF03070E));
    canvas.drawRect(
      panelRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = Colors.white.withValues(alpha: 0.34),
    );
    canvas.drawRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = panelBlue.withValues(alpha: 0.35),
    );

    final modeKey = '${game.cockpitMode.clamp(1, 6)}';
    final topY = body.top + 5;
    final leftTopRect = Rect.fromLTWH(
      body.left + 4,
      topY,
      body.width * 0.56 - 6,
      44,
    );
    final rightTopRect = Rect.fromLTWH(
      leftTopRect.right + 4,
      topY,
      body.right - leftTopRect.right - 8,
      83,
    );
    canvas.drawRect(leftTopRect, Paint()..color = const Color(0xFF0A1019));
    canvas.drawRect(
      leftTopRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFC0C8D2).withValues(alpha: 0.48),
    );
    final topName = target != null
        ? game.pirateContactName(target.pirate)
        : game.dockedStation?.name ??
              game.dockCandidate?.name ??
              game.sectorName.toUpperCase();
    _drawHudText(
      canvas,
      Offset(leftTopRect.left + 5, leftTopRect.top + 4),
      topName,
      color: panelAmber,
      size: 8.2,
      weight: FontWeight.w700,
    );
    final iconCenter = Offset(leftTopRect.center.dx, leftTopRect.bottom - 13);
    final shipIcon = Path()
      ..moveTo(iconCenter.dx, iconCenter.dy - 7)
      ..lineTo(iconCenter.dx + 8, iconCenter.dy + 2)
      ..lineTo(iconCenter.dx + 3, iconCenter.dy + 4)
      ..lineTo(iconCenter.dx, iconCenter.dy + 1)
      ..lineTo(iconCenter.dx - 3, iconCenter.dy + 4)
      ..lineTo(iconCenter.dx - 8, iconCenter.dy + 2)
      ..close();
    final iconColor = target == null
        ? const Color(0xFF93C5FD)
        : const Color(0xFFF87171);
    canvas.drawPath(
      shipIcon,
      Paint()..color = iconColor.withValues(alpha: 0.22),
    );
    canvas.drawPath(
      shipIcon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05
        ..color = iconColor.withValues(alpha: 0.84),
    );
    _drawHudText(
      canvas,
      Offset(leftTopRect.left + 5, leftTopRect.bottom - 10),
      target != null ? 'S/L' : 'NAV',
      color: panelText,
      size: 7.2,
      weight: FontWeight.w700,
    );

    canvas.drawRect(
      rightTopRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1730), Color(0xFF050A14)],
        ).createShader(rightTopRect),
    );
    canvas.drawRect(
      rightTopRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF87B5D9).withValues(alpha: 0.64),
    );
    final coordText =
        '${game.playerPosition.dx.round()}  ${game.playerPosition.dy.round()}';
    _drawHudText(
      canvas,
      Offset(rightTopRect.left + 4, rightTopRect.top + 3),
      coordText,
      color: const Color(0xFFE5D089),
      size: 7.6,
      weight: FontWeight.w700,
    );
    for (var i = 0; i < 12; i++) {
      final t = i / 11;
      final x =
          rightTopRect.left +
          6 +
          (i * 11) % math.max(10, (rightTopRect.width - 12).floor());
      final y = rightTopRect.top + 16 + t * (rightTopRect.height - 22);
      canvas.drawCircle(
        Offset(x, y),
        0.8,
        Paint()..color = const Color(0xFF8BC7F0).withValues(alpha: 0.7),
      );
    }
    final rowRect = Rect.fromLTWH(
      body.left + 4,
      leftTopRect.bottom + 4,
      body.width - 8,
      16,
    );
    canvas.drawRect(rowRect, Paint()..color = const Color(0xFF0D1520));
    canvas.drawRect(
      rowRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFF749AB8).withValues(alpha: 0.5),
    );
    _drawHudText(
      canvas,
      Offset(rowRect.left + 4, rowRect.top + 4),
      '[] TRACKING',
      color: panelText,
      size: 7.2,
      weight: FontWeight.w700,
    );
    _drawHudText(
      canvas,
      Offset(rowRect.center.dx + 2, rowRect.top + 4),
      '[] COMMUNICATE',
      color: panelText,
      size: 7.2,
      weight: FontWeight.w700,
    );

    final menuRect = Rect.fromLTWH(
      body.left + 4,
      rowRect.bottom + 4,
      body.width - 8,
      104,
    );
    canvas.drawRect(menuRect, Paint()..color = const Color(0xFF07101A));
    canvas.drawRect(
      menuRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = panelBlue.withValues(alpha: 0.45),
    );
    final menuRows = <String>[
      '1 CARGO/CONFIG',
      '2 ENGINEERING',
      '3 COMMUNICATE',
      '4 SCIENCE',
      '5 WEAPONS',
      '6 MISSIONS',
    ];
    final rowHeight = (menuRect.height - 8) / menuRows.length;
    for (var i = 0; i < menuRows.length; i++) {
      final entryRect = Rect.fromLTWH(
        menuRect.left + 3,
        menuRect.top + 3 + i * rowHeight,
        menuRect.width - 6,
        rowHeight - 1.3,
      );
      final key = '${i + 1}';
      final active = modeKey == key;
      canvas.drawRect(
        entryRect,
        Paint()
          ..color = (active ? const Color(0xFF173956) : const Color(0xFF091423))
              .withValues(alpha: active ? 0.96 : 0.8),
      );
      canvas.drawRect(
        entryRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = (active ? panelAmber : panelBlue).withValues(
            alpha: active ? 0.8 : 0.28,
          ),
      );
      _drawHudText(
        canvas,
        Offset(entryRect.left + 3, entryRect.top + 3),
        menuRows[i],
        color: active ? panelAmber : panelText,
        size: 7.3,
        weight: active ? FontWeight.w700 : FontWeight.w600,
      );
    }

    final powerRect = Rect.fromLTWH(
      body.left + 4,
      menuRect.bottom + 4,
      body.width - 8,
      84,
    );
    canvas.drawRect(powerRect, Paint()..color = const Color(0xFF07101A));
    canvas.drawRect(
      powerRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = panelBlue.withValues(alpha: 0.45),
    );
    _drawHudText(
      canvas,
      Offset(powerRect.left + 4, powerRect.top + 3),
      'POWER DIST.',
      color: panelAmber,
      size: 7.6,
      weight: FontWeight.w700,
    );
    final weaponPower = (game.power[PowerChannel.weapons]! / 100)
        .clamp(0.0, 1.0)
        .toDouble();
    final shieldPower = (game.playerShield / game.shieldCapacity)
        .clamp(0.0, 1.0)
        .toDouble();
    final enginePower = (game.power[PowerChannel.engines]! / 100)
        .clamp(0.0, 1.0)
        .toDouble();
    final sensorPower =
        ((game.playerEnergy / 100) * 0.7 +
                (game.power[PowerChannel.shields]! / 100) * 0.3)
            .clamp(0.0, 1.0)
            .toDouble();
    final powerRows = <({String label, double value, Color color})>[
      (label: 'W', value: weaponPower, color: const Color(0xFFF87171)),
      (label: 'L', value: shieldPower, color: const Color(0xFF60A5FA)),
      (label: 'E', value: enginePower, color: const Color(0xFF34D399)),
      (label: 'S', value: sensorPower, color: const Color(0xFFFBBF24)),
    ];
    final bandTop = powerRect.top + 16;
    final bandHeight = (powerRect.height - 20) / powerRows.length;
    for (var i = 0; i < powerRows.length; i++) {
      final row = powerRows[i];
      final y = bandTop + i * bandHeight;
      _drawHudText(
        canvas,
        Offset(powerRect.left + 4, y + 2),
        row.label,
        color: panelText,
        size: 7.3,
        weight: FontWeight.w700,
      );
      final leftBar = Rect.fromLTWH(
        powerRect.left + 16,
        y + 2,
        (powerRect.width - 26) * 0.46,
        bandHeight - 4,
      );
      final rightBar = Rect.fromLTWH(
        leftBar.right + 3,
        y + 2,
        (powerRect.width - 26) * 0.46,
        bandHeight - 4,
      );
      for (final bar in [leftBar, rightBar]) {
        canvas.drawRect(bar, Paint()..color = const Color(0xFF040A13));
        canvas.drawRect(
          bar,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = Colors.white.withValues(alpha: 0.18),
        );
      }
      final leftFill = Rect.fromLTWH(
        leftBar.left,
        leftBar.top,
        leftBar.width * row.value,
        leftBar.height,
      );
      final rightPulse =
          (row.value * (0.92 + 0.08 * math.sin(game._clock * 4.8 + i * 1.1)))
              .clamp(0.0, 1.0)
              .toDouble();
      final rightFill = Rect.fromLTWH(
        rightBar.left,
        rightBar.top,
        rightBar.width * rightPulse,
        rightBar.height,
      );
      if (leftFill.width > 0.2) {
        canvas.drawRect(
          leftFill,
          Paint()..color = row.color.withValues(alpha: 0.82),
        );
      }
      if (rightFill.width > 0.2) {
        canvas.drawRect(
          rightFill,
          Paint()..color = row.color.withValues(alpha: 0.72),
        );
      }
    }

    final podRect = Rect.fromLTRB(
      body.left + 4,
      powerRect.bottom + 4,
      body.right - 4,
      body.bottom - 4,
    );
    final podShape = RRect.fromRectAndCorners(
      podRect,
      topLeft: const Radius.circular(4),
      topRight: const Radius.circular(4),
      bottomLeft: const Radius.circular(34),
      bottomRight: const Radius.circular(34),
    );
    canvas.drawRRect(
      podShape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF20252D), Color(0xFF5E646D)],
        ).createShader(podRect),
    );
    final podInner = podRect.deflate(2);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        podInner,
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
        bottomLeft: const Radius.circular(31),
        bottomRight: const Radius.circular(31),
      ),
      Paint()..color = const Color(0xFF0A111B),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        podInner.left + 2,
        podInner.top + 2,
        podInner.width - 4,
        14,
      ),
      Paint()..color = const Color(0xFF0A2F53),
    );
    _drawHudText(
      canvas,
      Offset(podInner.left + 6, podInner.top + 5),
      'WEAPONS',
      color: panelAmber,
      size: 7.8,
      weight: FontWeight.w700,
    );
    _drawPanelMeter(
      canvas,
      Rect.fromLTWH(
        podInner.left + 5,
        podInner.top + 20,
        podInner.width - 10,
        10,
      ),
      label: 'MW',
      value: weaponPower,
      color: const Color(0xFFF87171),
    );
    _drawPanelMeter(
      canvas,
      Rect.fromLTWH(
        podInner.left + 5,
        podInner.top + 32,
        podInner.width - 10,
        10,
      ),
      label: 'C',
      value: target == null ? 0.42 : 0.86,
      color: const Color(0xFF60A5FA),
    );
    _drawHudText(
      canvas,
      Offset(podInner.left + 6, podInner.top + 46),
      game.jumpCandidate == null ? 'HYPERDRIVE F10' : 'HYPERDRIVE READY',
      color: game.jumpCandidate == null ? panelText : const Color(0xFF4ADE80),
      size: 7.2,
      weight: FontWeight.w700,
    );
    _drawHudText(
      canvas,
      Offset(podInner.left + 6, podInner.top + 57),
      'CARGO ${game.totalCargoUsed}/${game.cargoCapacity}',
      color: panelText,
      size: 7.2,
    );
    final warning = game.power[PowerChannel.weapons]! <= 15
        ? 'NO LASER POWER'
        : game.cockpitCommsPrompt == 'OBJECT MUST VISIBLE TO COMMUNICATE'
        ? 'OBJECT MUST VISIBLE TO COMMUNICATE'
        : target != null &&
              (target.projection.screen - reticleCenter).distance > 64
        ? 'OBJECT MUST BE ON SCREEN TO SCAN'
        : null;
    if (warning != null) {
      _drawHudText(
        canvas,
        Offset(podInner.left + 6, podInner.bottom - 12),
        warning,
        color: warning.contains('OBJECT')
            ? const Color(0xFFFDE68A)
            : panelWarning,
        size: 7.0,
        weight: FontWeight.w700,
      );
    }
  }

  void _drawControlPanelDosCompact(
    Canvas canvas,
    Size size, {
    required _TargetSnapshot? target,
    required Offset reticleCenter,
  }) {
    const steelTop = Color(0xFF9299A4);
    const steelMid = Color(0xFF4D5560);
    const steelBottom = Color(0xFFA2A9B2);
    const panelBlue = Color(0xFF7BB7DF);
    const panelAmber = Color(0xFFE5D089);
    const panelText = Color(0xFFC6D6E4);
    final panelRect = _panelRectFor(size);
    final body = panelRect.deflate(1.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, const Radius.circular(1.4)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [steelTop, steelMid, steelBottom],
        ).createShader(panelRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(1.0)),
      Paint()..color = const Color(0xFF040913),
    );
    canvas.drawRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = panelBlue.withValues(alpha: 0.34),
    );

    final mapRect = Rect.fromLTWH(
      body.left + 2,
      body.top + 2,
      body.width - 4,
      38,
    );
    final mode = game.cockpitMode.clamp(1, 6);
    _drawCompactPreview(
      canvas,
      mapRect,
      mode: mode,
      target: target,
      panelAmber: panelAmber,
      panelBlue: panelBlue,
      panelText: panelText,
    );

    if (mode == 1 || mode == 2) {
      final fullRect = Rect.fromLTWH(
        body.left + 2,
        mapRect.bottom + 2,
        body.width - 4,
        body.bottom - mapRect.bottom - 4,
      );
      if (mode == 1) {
        _drawCompactCargoScreen(
          canvas,
          fullRect,
          panelAmber: panelAmber,
          panelBlue: panelBlue,
          panelText: panelText,
        );
      } else {
        _drawCompactEngineeringScreen(
          canvas,
          fullRect,
          panelAmber: panelAmber,
          panelBlue: panelBlue,
          panelText: panelText,
        );
      }
      return;
    }

    final modeKey = '$mode';
    final rowRect = Rect.fromLTWH(
      body.left + 2,
      mapRect.bottom + 2,
      body.width - 4,
      10,
    );
    canvas.drawRect(rowRect, Paint()..color = const Color(0xFF0B1521));
    canvas.drawRect(
      rowRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = const Color(0xFF749AB8).withValues(alpha: 0.5),
    );
    _drawHudText(
      canvas,
      Offset(rowRect.left + 2, rowRect.top + 2),
      '[]TRK',
      color: panelText,
      size: 4.5,
      weight: FontWeight.w700,
    );
    _drawHudText(
      canvas,
      Offset(rowRect.center.dx + 1, rowRect.top + 2),
      '[]COM',
      color: panelText,
      size: 4.5,
      weight: FontWeight.w700,
    );

    final menuRect = Rect.fromLTWH(
      body.left + 2,
      rowRect.bottom + 2,
      body.width - 4,
      58,
    );
    canvas.drawRect(menuRect, Paint()..color = const Color(0xFF07111B));
    canvas.drawRect(
      menuRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = panelBlue.withValues(alpha: 0.42),
    );
    final menuRows = <String>[
      '1 CARGO/CONFIG',
      '2 ENGINEERING',
      '3 COMMUNICATE',
      '4 SCIENCE',
      '5 WEAPONS',
      '6 MISSIONS',
    ];
    final rowHeight = (menuRect.height - 6) / menuRows.length;
    for (var i = 0; i < menuRows.length; i++) {
      final entryRect = Rect.fromLTWH(
        menuRect.left + 1.5,
        menuRect.top + 1.5 + i * rowHeight,
        menuRect.width - 3,
        rowHeight - 0.7,
      );
      final active = '${i + 1}' == modeKey;
      canvas.drawRect(
        entryRect,
        Paint()
          ..color = (active ? const Color(0xFF1A3854) : const Color(0xFF091423))
              .withValues(alpha: active ? 0.95 : 0.82),
      );
      canvas.drawRect(
        entryRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = (active ? panelAmber : panelBlue).withValues(
            alpha: active ? 0.82 : 0.22,
          ),
      );
      _drawHudText(
        canvas,
        Offset(entryRect.left + 1.8, entryRect.top + 1.4),
        menuRows[i],
        color: active ? panelAmber : panelText,
        size: 4.35,
        weight: active ? FontWeight.w700 : FontWeight.w600,
      );
    }

    final powerRect = Rect.fromLTWH(
      body.left + 2,
      menuRect.bottom + 2,
      body.width - 4,
      42,
    );
    _drawCompactPowerGrid(
      canvas,
      powerRect,
      panelAmber: panelAmber,
      panelBlue: panelBlue,
      panelText: panelText,
    );

    final podRect = Rect.fromLTWH(
      body.left + 2,
      powerRect.bottom + 2,
      body.width - 4,
      body.bottom - powerRect.bottom - 4,
    );
    _drawCompactAuxScreen(
      canvas,
      podRect,
      mode: mode,
      target: target,
      reticleCenter: reticleCenter,
      panelAmber: panelAmber,
      panelBlue: panelBlue,
      panelText: panelText,
    );
  }

  void _drawCompactPreview(
    Canvas canvas,
    Rect rect, {
    required int mode,
    required _TargetSnapshot? target,
    required Color panelAmber,
    required Color panelBlue,
    required Color panelText,
  }) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFF051122));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = panelBlue.withValues(alpha: 0.58),
    );
    final coordText =
        '${game.playerPosition.dx.round()}  ${game.playerPosition.dy.round()}';
    _drawHudText(
      canvas,
      Offset(rect.left + 2, rect.top + 2),
      coordText,
      color: panelAmber,
      size: 5.0,
      weight: FontWeight.w700,
    );

    if ((mode == 4 || mode == 5) && target != null) {
      _drawHudText(
        canvas,
        Offset(rect.left + 2, rect.top + 9),
        _compactText(game.pirateHullClass(target.pirate), 8),
        color: panelText,
        size: 4.2,
        weight: FontWeight.w700,
      );
      _drawPirateSprite(
        canvas,
        Offset(rect.center.dx, rect.top + 25),
        size: 9.5,
        tracked: true,
        yaw: target.pirate.angle,
      );
      if (mode == 5) {
        final meter = Rect.fromLTWH(
          rect.left + 4,
          rect.bottom - 8,
          rect.width - 8,
          4,
        );
        canvas.drawRect(meter, Paint()..color = const Color(0xFF07101A));
        final fill = Rect.fromLTWH(
          meter.left,
          meter.top,
          meter.width * (target.pirate.hull / 44).clamp(0.0, 1.0),
          meter.height,
        );
        canvas.drawRect(fill, Paint()..color = const Color(0xFFF87171));
      }
      return;
    }

    if (mode == 3 && game.activeEncounter != null) {
      _drawHudText(
        canvas,
        Offset(rect.left + 2, rect.top + 10),
        'INCOMING HAIL',
        color: panelAmber,
        size: 4.7,
        weight: FontWeight.w700,
      );
      _drawHudText(
        canvas,
        Offset(rect.left + 2, rect.top + 18),
        _compactText(game.activeEncounter!.title.toUpperCase(), 12),
        color: panelText,
        size: 4.3,
      );
      return;
    }

    for (var i = 0; i < 8; i++) {
      final x = rect.left + 6 + (i * 9) % math.max(8, rect.width.toInt() - 10);
      final y = rect.top + 11 + (i % 4) * 6.0;
      canvas.drawCircle(
        Offset(x, y),
        0.65,
        Paint()..color = const Color(0xFF8BC7F0).withValues(alpha: 0.75),
      );
    }
  }

  void _drawCompactCargoScreen(
    Canvas canvas,
    Rect rect, {
    required Color panelAmber,
    required Color panelBlue,
    required Color panelText,
  }) {
    final header = Rect.fromLTWH(rect.left, rect.top, rect.width, 10);
    canvas.drawRect(header, Paint()..color = const Color(0xFF0A2F53));
    _drawHudText(
      canvas,
      Offset(header.left + 2, header.top + 2),
      'CARGO',
      color: panelAmber,
      size: 4.8,
      weight: FontWeight.w700,
    );
    final podRect = Rect.fromLTWH(
      rect.left,
      header.bottom + 1,
      rect.width,
      rect.height - 11,
    );
    final podShape = RRect.fromRectAndCorners(
      podRect,
      topLeft: const Radius.circular(1.2),
      topRight: const Radius.circular(1.2),
      bottomLeft: const Radius.circular(17),
      bottomRight: const Radius.circular(17),
    );
    canvas.drawRRect(
      podShape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF242A31), Color(0xFF5F656E)],
        ).createShader(podRect),
    );
    final podInner = podRect.deflate(1.4);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        podInner,
        topLeft: const Radius.circular(1),
        topRight: const Radius.circular(1),
        bottomLeft: const Radius.circular(16),
        bottomRight: const Radius.circular(16),
      ),
      Paint()..color = const Color(0xFF10161F),
    );

    final canister = Rect.fromCenter(
      center: Offset(podInner.center.dx, podInner.top + 19),
      width: 20,
      height: 12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(canister, const Radius.circular(2)),
      Paint()..color = const Color(0xFF395D8A),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        canister.left + 2,
        canister.top + 2,
        canister.width - 4,
        2.5,
      ),
      Paint()..color = const Color(0xFF9CC7E7),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        canister.left + 6,
        canister.top + 5,
        canister.width - 12,
        4,
      ),
      Paint()..color = const Color(0xFFD8B35A),
    );
    _drawHudText(
      canvas,
      Offset(podInner.left + 5, canister.center.dy - 1.5),
      '<',
      color: panelText,
      size: 5.0,
      weight: FontWeight.w700,
    );
    _drawHudText(
      canvas,
      Offset(podInner.right - 7, canister.center.dy - 1.5),
      '>',
      color: panelText,
      size: 5.0,
      weight: FontWeight.w700,
    );

    final cargoLabel = _compactCargoLabel();
    _drawHudText(
      canvas,
      Offset(podInner.left + 3, podInner.top + 33),
      _compactText(cargoLabel, 12),
      color: panelAmber,
      size: 4.6,
      weight: FontWeight.w700,
    );
    _drawHudText(
      canvas,
      Offset(podInner.left + 3, podInner.top + 40),
      game.activeContract != null ? 'TRANSPORT' : 'CONVERTER',
      color: panelText,
      size: 4.2,
    );
    _drawHudText(
      canvas,
      Offset(podInner.left + 3, podInner.top + 46),
      game.activeContract != null
          ? 'UNITS ${game.activeContract!.cargoUnits}'
          : 'USE',
      color: panelText,
      size: 4.2,
    );
    _drawHudText(
      canvas,
      Offset(podInner.left + 3, podInner.bottom - 7),
      'FREE ${game.freeCargoSpace}/${game.cargoCapacity}',
      color: panelBlue,
      size: 4.0,
      weight: FontWeight.w700,
    );
  }

  void _drawCompactEngineeringScreen(
    Canvas canvas,
    Rect rect, {
    required Color panelAmber,
    required Color panelBlue,
    required Color panelText,
  }) {
    final header = Rect.fromLTWH(rect.left, rect.top, rect.width, 10);
    canvas.drawRect(header, Paint()..color = const Color(0xFF0A2F53));
    _drawHudText(
      canvas,
      Offset(header.left + 2, header.top + 2),
      'ENGINEERING',
      color: panelAmber,
      size: 4.5,
      weight: FontWeight.w700,
    );
    final statsRect = Rect.fromLTWH(
      rect.left,
      header.bottom + 1,
      rect.width,
      rect.height - 11,
    );
    canvas.drawRect(statsRect, Paint()..color = const Color(0xFF10161F));
    canvas.drawRect(
      statsRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = panelBlue.withValues(alpha: 0.36),
    );
    _drawHudText(
      canvas,
      Offset(statsRect.left + 2, statsRect.top + 2),
      'POWER DIST.',
      color: panelAmber,
      size: 4.6,
      weight: FontWeight.w700,
    );
    final values = <({String label, double value, Color color})>[
      (
        label: 'WE',
        value: (game.power[PowerChannel.weapons]! / 100)
            .clamp(0.0, 1.0)
            .toDouble(),
        color: const Color(0xFFF87171),
      ),
      (
        label: 'EN',
        value: (game.power[PowerChannel.engines]! / 100)
            .clamp(0.0, 1.0)
            .toDouble(),
        color: const Color(0xFF34D399),
      ),
      (
        label: 'SH',
        value: (game.playerShield / game.shieldCapacity)
            .clamp(0.0, 1.0)
            .toDouble(),
        color: const Color(0xFF60A5FA),
      ),
      (
        label: 'SE',
        value: ((game.playerEnergy / 100) * 0.7).clamp(0.0, 1.0).toDouble(),
        color: const Color(0xFFFBBF24),
      ),
    ];
    final barTop = statsRect.top + 11;
    for (var i = 0; i < values.length; i++) {
      final x = statsRect.left + 5 + i * 11.0;
      final outer = Rect.fromLTWH(x, barTop, 8, 21);
      canvas.drawRect(outer, Paint()..color = const Color(0xFF07101A));
      canvas.drawRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = Colors.white.withValues(alpha: 0.18),
      );
      final fillHeight = outer.height * values[i].value;
      final fill = Rect.fromLTWH(
        outer.left + 1,
        outer.bottom - fillHeight,
        outer.width - 2,
        fillHeight,
      );
      if (fill.height > 0.2) {
        canvas.drawRect(
          fill,
          Paint()..color = values[i].color.withValues(alpha: 0.88),
        );
      }
      _drawHudText(
        canvas,
        Offset(outer.left - 0.5, outer.bottom + 1),
        values[i].label,
        color: panelText,
        size: 3.9,
        weight: FontWeight.w700,
      );
    }
    _drawHudText(
      canvas,
      Offset(statsRect.left + 2, statsRect.top + 38),
      'REACTOR ${(game.playerEnergy).round()}%',
      color: panelText,
      size: 4.3,
      weight: FontWeight.w700,
    );
    _drawHudText(
      canvas,
      Offset(statsRect.left + 2, statsRect.top + 45),
      'AVAILABLE ${game.totalPowerAllocation}%',
      color: panelText,
      size: 4.1,
    );
    _drawHudText(
      canvas,
      Offset(statsRect.left + 2, statsRect.bottom - 7),
      'SHIELDS ${(game.playerShield).round()}  FUEL ${game.playerFuel.round()}',
      color: panelBlue,
      size: 3.9,
      weight: FontWeight.w700,
    );
  }

  void _drawCompactPowerGrid(
    Canvas canvas,
    Rect rect, {
    required Color panelAmber,
    required Color panelBlue,
    required Color panelText,
  }) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFF07101A));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = panelBlue.withValues(alpha: 0.4),
    );
    _drawHudText(
      canvas,
      Offset(rect.left + 2, rect.top + 1),
      'POWER DIST.',
      color: panelAmber,
      size: 4.8,
      weight: FontWeight.w700,
    );
    final powerRows = <({String label, double value, Color color})>[
      (
        label: 'W',
        value: (game.power[PowerChannel.weapons]! / 100)
            .clamp(0.0, 1.0)
            .toDouble(),
        color: const Color(0xFFF87171),
      ),
      (
        label: 'L',
        value: (game.playerShield / game.shieldCapacity)
            .clamp(0.0, 1.0)
            .toDouble(),
        color: const Color(0xFF60A5FA),
      ),
      (
        label: 'E',
        value: (game.power[PowerChannel.engines]! / 100)
            .clamp(0.0, 1.0)
            .toDouble(),
        color: const Color(0xFF34D399),
      ),
      (
        label: 'S',
        value:
            ((game.playerEnergy / 100) * 0.7 +
                    (game.power[PowerChannel.shields]! / 100) * 0.3)
                .clamp(0.0, 1.0)
                .toDouble(),
        color: const Color(0xFFFBBF24),
      ),
    ];
    final bandHeight = (rect.height - 10) / powerRows.length;
    for (var i = 0; i < powerRows.length; i++) {
      final row = powerRows[i];
      final y = rect.top + 8 + i * bandHeight;
      _drawHudText(
        canvas,
        Offset(rect.left + 2, y + 0.9),
        row.label,
        color: panelText,
        size: 4.4,
        weight: FontWeight.w700,
      );
      final barRect = Rect.fromLTWH(
        rect.left + 8,
        y + 1.2,
        rect.width - 10,
        bandHeight - 2.1,
      );
      canvas.drawRect(barRect, Paint()..color = const Color(0xFF050C16));
      canvas.drawRect(
        barRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.55
          ..color = Colors.white.withValues(alpha: 0.18),
      );
      final fillRect = Rect.fromLTWH(
        barRect.left,
        barRect.top,
        barRect.width * row.value,
        barRect.height,
      );
      if (fillRect.width > 0.1) {
        canvas.drawRect(
          fillRect,
          Paint()..color = row.color.withValues(alpha: 0.84),
        );
      }
    }
  }

  void _drawCompactAuxScreen(
    Canvas canvas,
    Rect rect, {
    required int mode,
    required _TargetSnapshot? target,
    required Offset reticleCenter,
    required Color panelAmber,
    required Color panelBlue,
    required Color panelText,
  }) {
    const panelWarning = Color(0xFFFCA5A5);
    final shell = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(1.2),
      topRight: const Radius.circular(1.2),
      bottomLeft: const Radius.circular(17),
      bottomRight: const Radius.circular(17),
    );
    canvas.drawRRect(
      shell,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1F252C), Color(0xFF59606A)],
        ).createShader(rect),
    );
    final innerRect = rect.deflate(1.2);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        innerRect,
        topLeft: const Radius.circular(1),
        topRight: const Radius.circular(1),
        bottomLeft: const Radius.circular(16),
        bottomRight: const Radius.circular(16),
      ),
      Paint()..color = const Color(0xFF0A111B),
    );

    final title = switch (mode) {
      3 => 'COMMUNICATE',
      4 => 'SCIENCE',
      5 => 'WEAPONS',
      6 => 'MISSIONS',
      _ => 'SYSTEM',
    };
    _drawHudText(
      canvas,
      Offset(innerRect.left + 2, innerRect.top + 1),
      title,
      color: panelAmber,
      size: 4.8,
      weight: FontWeight.w700,
    );

    if (mode == 3) {
      final titleText =
          game.activeEncounter?.title ??
          (game.nearestStation != null
              ? '${game.nearestStation!.name} RELAY'
              : 'NO RESPONSE');
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 8),
        _compactText(titleText.toUpperCase(), 13),
        color: panelText,
        size: 4.5,
        weight: FontWeight.w700,
      );
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 14),
        game.activeEncounter != null
            ? 'RESP 1-${game.activeEncounter!.options.length}'
            : 'PRESS C',
        color: panelBlue,
        size: 4.2,
      );
    } else if (mode == 4) {
      final label = target == null
          ? 'NO TARGET'
          : game.pirateContactName(target.pirate);
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 8),
        _compactText(label, 13),
        color: panelText,
        size: 4.5,
        weight: FontWeight.w700,
      );
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 14),
        target == null
            ? 'SCAN READY'
            : 'SHIELD ${game.pirateShieldType(target.pirate)}',
        color: const Color(0xFF93C5FD),
        size: 4.2,
      );
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 20),
        target == null
            ? 'OBJECT MUST BE ON SCREEN TO SCAN'
            : 'CANNON ${game.pirateCannonType(target.pirate)}',
        color: target == null ? const Color(0xFFFDE68A) : panelText,
        size: 4.0,
      );
    } else if (mode == 5) {
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 8),
        target == null
            ? 'MW ${(game.power[PowerChannel.weapons]!)}'
            : 'MW TRACK',
        color: panelText,
        size: 4.5,
        weight: FontWeight.w700,
      );
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 14),
        target == null ? 'MISSILES STBY' : 'MISSILES TRACK',
        color: panelBlue,
        size: 4.2,
      );
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 20),
        game.jumpCandidate == null ? 'HYPERDRIVE F10' : 'HYPERDRIVE READY',
        color: panelText,
        size: 4.0,
      );
    } else if (mode == 6) {
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 8),
        _compactText(game.campaignTitle.toUpperCase(), 13),
        color: panelText,
        size: 4.4,
        weight: FontWeight.w700,
      );
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.top + 14),
        'PROGRESS ${game.campaignProgressText}',
        color: panelBlue,
        size: 4.2,
      );
      if (game.activeContract != null) {
        _drawHudText(
          canvas,
          Offset(innerRect.left + 2, innerRect.top + 20),
          _compactText(game.activeContract!.cargoName.toUpperCase(), 13),
          color: panelText,
          size: 4.0,
        );
      }
    }

    _drawHudText(
      canvas,
      Offset(innerRect.left + 2, innerRect.bottom - 12),
      'CARGO ${game.totalCargoUsed}/${game.cargoCapacity}',
      color: panelText,
      size: 4.1,
    );
    final warning = game.power[PowerChannel.weapons]! <= 15
        ? 'NO LASER POWER'
        : game.cockpitCommsPrompt == 'OBJECT MUST VISIBLE TO COMMUNICATE'
        ? 'OBJECT MUST VISIBLE TO COMMUNICATE'
        : target != null &&
              (target.projection.screen - reticleCenter).distance > 64 &&
              mode == 4
        ? 'OBJECT MUST BE ON SCREEN TO SCAN'
        : null;
    if (warning != null) {
      _drawHudText(
        canvas,
        Offset(innerRect.left + 2, innerRect.bottom - 6.5),
        warning,
        color: warning.contains('OBJECT')
            ? const Color(0xFFFDE68A)
            : panelWarning,
        size: 4.0,
        weight: FontWeight.w700,
      );
    }
  }

  String _compactCargoLabel() {
    final active = game.activeContract;
    if (active != null) {
      return active.cargoName.toUpperCase();
    }
    final offer = game.currentDockOffer;
    if (offer != null) {
      return offer.cargoName.toUpperCase();
    }
    return 'CONVERTER';
  }

  String _compactText(String text, int maxChars) {
    final normalized = text.replaceAll('\n', ' ').trim();
    if (normalized.length <= maxChars) {
      return normalized;
    }
    return '${normalized.substring(0, maxChars - 1)}.';
  }

  void _drawPanelMeter(
    Canvas canvas,
    Rect rect, {
    required String label,
    required double value,
    required Color color,
  }) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    final labelWidth = math.min(40.0, rect.width * 0.28);
    final barRect = Rect.fromLTWH(
      rect.left + labelWidth,
      rect.top + 1,
      rect.width - labelWidth,
      rect.height - 2,
    );
    canvas.drawRect(barRect, Paint()..color = const Color(0xFF070F17));
    for (var i = 1; i < 8; i++) {
      final x = barRect.left + barRect.width * i / 8;
      canvas.drawLine(
        Offset(x, barRect.top),
        Offset(x, barRect.bottom),
        Paint()..color = Colors.white.withValues(alpha: 0.04),
      );
    }
    final fillWidth = barRect.width * clamped;
    if (fillWidth > 0.2) {
      final fill = Rect.fromLTWH(
        barRect.left,
        barRect.top,
        fillWidth,
        barRect.height,
      );
      canvas.drawRect(
        fill,
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: 0.5),
              color.withValues(alpha: 0.98),
            ],
          ).createShader(fill),
      );
    }
    canvas.drawRect(
      barRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = Colors.white.withValues(alpha: 0.16),
    );
    _drawHudText(
      canvas,
      Offset(rect.left + 1, rect.top + 0.4),
      label,
      color: const Color(0xFFC8D9E8),
      size: 7.4,
      weight: FontWeight.w700,
    );
    final pctLabel = '${(clamped * 100).round()}';
    _drawHudText(
      canvas,
      Offset(barRect.right - 16, rect.top + 0.4),
      pctLabel,
      color: const Color(0xFFE5D089),
      size: 7.2,
      weight: FontWeight.w700,
    );
  }

  void _drawHudText(
    Canvas canvas,
    Offset pos,
    String text, {
    Color color = const Color(0xFFC9E3F4),
    double size = 10,
    FontWeight weight = FontWeight.w600,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          height: 1.0,
          letterSpacing: 0.42,
          fontFamilyFallback: const ['Menlo', 'Monaco', 'Courier New'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 360);
    tp.paint(canvas, pos);
  }

  void _drawDosCrtOverlay(Canvas canvas, Rect viewportRect) {
    final linePaint = Paint()
      ..isAntiAlias = false
      ..strokeWidth = 1;
    for (double y = viewportRect.top; y <= viewportRect.bottom; y += 2) {
      linePaint.color = const Color(0xFF0A111C).withValues(alpha: 0.18);
      canvas.drawLine(
        Offset(viewportRect.left, y),
        Offset(viewportRect.right, y),
        linePaint,
      );
    }
    canvas.drawRect(
      viewportRect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.04,
          colors: [
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.28),
          ],
          stops: const [0.55, 0.82, 1.0],
        ).createShader(viewportRect),
    );
  }

  void _drawPostProcessing(
    Canvas canvas,
    Rect viewportRect, {
    required double speedFactor,
  }) {
    final rect = viewportRect;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          center: const Alignment(0, -0.14),
          radius: 1.08,
          colors: [
            const Color(0xFF7AC7FF).withValues(alpha: 0.1),
            const Color(0xFF27486E).withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const [0.0, 0.38, 1.0],
        ).createShader(rect),
    );

    if (speedFactor > 0.18) {
      final streakPaint = Paint()
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.screen;
      for (var i = 0; i < 12; i++) {
        final t = i / 11;
        final x = rect.left + rect.width * (0.14 + t * 0.72);
        final amplitude = rect.height * 0.1 * math.sin(game._clock * 0.9 + i);
        final top = Offset(x, rect.top + rect.height * 0.22 + amplitude);
        final bottom = Offset(x, rect.bottom - rect.height * 0.08);
        streakPaint
          ..strokeWidth = 0.8 + speedFactor * 1.8
          ..color = const Color(0xFF7DD3FC).withValues(
            alpha: 0.018 + speedFactor * 0.05,
          );
        canvas.drawLine(top, bottom, streakPaint);
      }
    }

    final speedBloom = (0.03 + speedFactor * 0.13).clamp(0.03, 0.18).toDouble();
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF4B84B8).withValues(alpha: speedBloom),
            Colors.transparent,
          ],
          stops: const [0.0, 0.82, 1.0],
        ).createShader(rect),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.08,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.12),
            Colors.black.withValues(alpha: 0.34),
          ],
          stops: const [0.62, 0.86, 1.0],
        ).createShader(rect),
    );
  }

  void _drawMesh(
    Canvas canvas, {
    required Offset center,
    required double focal,
    required _MeshModel mesh,
    required _Vec3 origin,
    required double yaw,
    required Color baseColor,
    required _Vec3 lightDir,
    required double ambient,
    required double emissiveBoost,
    required double edgeAlpha,
    double scale = 1,
  }) {
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final viewVertices = List<_Vec3>.filled(mesh.vertices.length, _Vec3.zero);
    final projected = List<_ProjectedPoint?>.filled(mesh.vertices.length, null);

    for (var i = 0; i < mesh.vertices.length; i++) {
      final v = mesh.vertices[i];
      final scaled = _Vec3(v.x * scale, v.y * scale, v.z * scale);
      final rotated = _Vec3(
        scaled.x * cy - scaled.z * sy,
        scaled.y,
        scaled.x * sy + scaled.z * cy,
      );
      final view = origin + rotated;
      viewVertices[i] = view;
      projected[i] = _project3D(
        center: center,
        focal: focal,
        right: view.x,
        up: view.y,
        forward: view.z,
      );
    }

    final tris = <_MeshTriangle>[];
    for (final face in mesh.faces) {
      if (face.indices.length < 3) {
        continue;
      }
      for (var i = 1; i < face.indices.length - 1; i++) {
        final ia = face.indices[0];
        final ib = face.indices[i];
        final ic = face.indices[i + 1];
        final pa = projected[ia];
        final pb = projected[ib];
        final pc = projected[ic];
        if (pa == null || pb == null || pc == null) {
          continue;
        }

        final va = viewVertices[ia];
        final vb = viewVertices[ib];
        final vc = viewVertices[ic];
        final normal = (vb - va).cross(vc - va).normalized();
        final centroid = (va + vb + vc) / 3;
        final toCamera = (-centroid).normalized();
        var facing = normal.dot(toCamera);
        if (face.doubleSided) {
          facing = facing.abs();
        }
        if (facing <= 0.01) {
          continue;
        }

        final diffuse = math.max(0, normal.dot(lightDir));
        final headlight = toCamera.z.clamp(0.0, 1.0).toDouble();
        final halfVector = (lightDir + toCamera).normalized();
        final specular = math
            .pow(math.max(0, normal.dot(halfVector)), 22)
            .toDouble();
        final rim = math
            .pow((1 - math.max(0, normal.dot(toCamera))).clamp(0.0, 1.0), 2)
            .toDouble();
        final emissivePulse =
            0.75 +
            0.25 *
                math.sin(
                  game._clock * 5.2 + centroid.z * 0.02 + centroid.x * 0.01,
                );
        final brightness =
            (ambient +
                    diffuse * 0.56 +
                    headlight * 0.2 +
                    facing * 0.2 +
                    specular * 0.45 +
                    rim * 0.14 +
                    face.tone +
                    (face.emissive + emissiveBoost) * emissivePulse)
                .clamp(0.05, 1.9)
                .toDouble();
        final fade = (1 - centroid.z / _farClip).clamp(0.12, 1.0).toDouble();
        final fill = _shadeColor(baseColor, brightness, fade * 0.96);
        final stroke = _shadeColor(
          baseColor,
          brightness * (0.84 + specular * 0.16),
          fade * edgeAlpha,
        );
        tris.add(
          _MeshTriangle(
            points: [pa.screen, pb.screen, pc.screen],
            depth: centroid.z,
            fill: fill,
            stroke: stroke,
          ),
        );
      }
    }

    tris.sort((a, b) => b.depth.compareTo(a.depth));
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (final tri in tris) {
      final path = Path()
        ..moveTo(tri.points[0].dx, tri.points[0].dy)
        ..lineTo(tri.points[1].dx, tri.points[1].dy)
        ..lineTo(tri.points[2].dx, tri.points[2].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = tri.fill);
      strokePaint.color = tri.stroke;
      canvas.drawPath(path, strokePaint);
    }
  }

  Color _shadeColor(Color base, double intensity, double alpha) {
    final t = intensity.clamp(0.0, 2.0).toDouble();
    final lit = t <= 1
        ? Color.lerp(Colors.black, base, t)!
        : Color.lerp(base, Colors.white, t - 1)!;
    return lit.withValues(alpha: alpha.clamp(0.0, 1.0).toDouble());
  }

  static _MeshModel _buildPlayerMesh() {
    final vertices = <_Vec3>[
      const _Vec3(0, 3.5, 46), // 0: Nose tip
      const _Vec3(-12, 5.5, 18), // 1: Cockpit front left
      const _Vec3(12, 5.5, 18), // 2: Cockpit front right
      const _Vec3(-38, 1.5, -8), // 3: Left wing tip
      const _Vec3(38, 1.5, -8), // 4: Right wing tip
      const _Vec3(-14, -2.5, -34), // 5: Rear left
      const _Vec3(14, -2.5, -34), // 6: Rear right
      const _Vec3(0, 16, -10), // 7: Tail fin top
      const _Vec3(0, -9, -14), // 8: Ventral scoop
      const _Vec3(0, 1.5, -44), // 9: Rear center (engine block)
      const _Vec3(-6, 0.8, 6), // 10: Lower front left
      const _Vec3(6, 0.8, 6), // 11: Lower front right
      const _Vec3(-18, 2.5, -16), // 12: Mid left body
      const _Vec3(18, 2.5, -16), // 13: Mid right body
      const _Vec3(-6, 8.5, -4), // 14: Cockpit roof left
      const _Vec3(6, 8.5, -4), // 15: Cockpit roof right
      const _Vec3(-22, 5.0, -32), // 16: Left wing trailing root
      const _Vec3(22, 5.0, -32), // 17: Right wing trailing root
    ];

    final faces = <_MeshFace>[
      // Nose cone
      _MeshFace(
        [0, 1, 14, 15, 2],
        tone: 0.15,
        emissive: 0.04,
        doubleSided: true,
      ),
      _MeshFace([0, 10, 1], tone: 0.08, doubleSided: true),
      _MeshFace([0, 2, 11], tone: 0.08, doubleSided: true),
      _MeshFace([0, 11, 8, 10], tone: -0.05, doubleSided: true),

      // Cockpit / Canopy
      _MeshFace(
        [1, 14, 15, 2],
        tone: -0.1,
        emissive: 0.15,
        doubleSided: true,
      ), // Glass
      // Main Fuselage
      _MeshFace([1, 12, 14], tone: 0.05, doubleSided: true),
      _MeshFace([2, 15, 13], tone: 0.05, doubleSided: true),
      _MeshFace([14, 7, 15], tone: 0.12, emissive: 0.02, doubleSided: true),
      _MeshFace([12, 5, 14], tone: 0.02, doubleSided: true),
      _MeshFace([13, 15, 6], tone: 0.02, doubleSided: true),
      _MeshFace(
        [14, 5, 9, 6, 15],
        tone: 0.04,
        doubleSided: true,
      ), // Upper rear deck
      // Wings
      _MeshFace(
        [12, 3, 16, 5],
        tone: -0.02,
        emissive: 0.03,
        doubleSided: true,
      ), // Left wing
      _MeshFace(
        [13, 6, 17, 4],
        tone: -0.02,
        emissive: 0.03,
        doubleSided: true,
      ), // Right wing
      _MeshFace(
        [1, 10, 3, 12],
        tone: 0.02,
        doubleSided: true,
      ), // Left wing root blend
      _MeshFace(
        [2, 13, 4, 11],
        tone: 0.02,
        doubleSided: true,
      ), // Right wing root blend
      // Ventral / Undercarriage
      _MeshFace([10, 8, 3], tone: -0.1, doubleSided: true),
      _MeshFace([11, 4, 8], tone: -0.1, doubleSided: true),
      _MeshFace([3, 8, 5], tone: -0.08, doubleSided: true),
      _MeshFace([4, 6, 8], tone: -0.08, doubleSided: true),
      _MeshFace(
        [5, 8, 9, 6],
        tone: -0.15,
        emissive: 0.08,
        doubleSided: true,
      ), // Engine block bottom
      // Tail fin
      _MeshFace([14, 7, 9], tone: 0.06, doubleSided: true),
      _MeshFace([15, 9, 7], tone: 0.06, doubleSided: true),
    ];

    return _MeshModel(vertices: vertices, faces: faces);
  }

  static _MeshModel _buildPirateMesh() {
    final vertices = <_Vec3>[
      const _Vec3(0, 2.0, 42), // Extended nose tip
    ];

    List<int> addRing(
      double z,
      double xRadius,
      double yRadius, {
      double y = 0,
      double scaleXTop = 1.0,
      double scaleXBot = 1.0,
    }) {
      final start = vertices.length;
      vertices.add(_Vec3(-xRadius * scaleXTop, y + yRadius, z));
      vertices.add(_Vec3(xRadius * scaleXTop, y + yRadius, z));
      vertices.add(_Vec3(xRadius * scaleXBot, y - yRadius, z));
      vertices.add(_Vec3(-xRadius * scaleXBot, y - yRadius, z));
      return <int>[start, start + 1, start + 2, start + 3];
    }

    // A more aggressive, swept-forward fuselage profile for the pirate ships
    final ring1 = addRing(24, 5.0, 2.5, y: 0.5, scaleXTop: 0.6);
    final ring2 = addRing(8, 9.5, 4.8, y: 1.0, scaleXTop: 0.8, scaleXBot: 1.2);
    final ring3 = addRing(-8, 9.0, 4.0, y: 0.5, scaleXBot: 1.3);
    final ring4 = addRing(-28, 5.5, 2.8, scaleXTop: 0.9);
    final aftCenter = vertices.length;
    vertices.add(const _Vec3(0, 0, -42)); // Extended tail

    // Aggressive forward-swept winglets
    final leftTipTop = vertices.length;
    vertices.add(const _Vec3(-38, 2.4, -2));
    final leftTipBottom = vertices.length;
    vertices.add(const _Vec3(-35, -3.2, -6));
    final rightTipTop = vertices.length;
    vertices.add(const _Vec3(38, 2.4, -2));
    final rightTipBottom = vertices.length;
    vertices.add(const _Vec3(35, -3.2, -6));

    // Weapons pods on inner wings
    final leftWeapon = vertices.length;
    vertices.add(const _Vec3(-18, 0, 12));
    final rightWeapon = vertices.length;
    vertices.add(const _Vec3(18, 0, 12));

    final leftEngine = vertices.length;
    vertices.add(const _Vec3(-14, -1.2, -26));
    final rightEngine = vertices.length;
    vertices.add(const _Vec3(14, -1.2, -26));

    // Stabilizers
    final dorsalTip = vertices.length;
    vertices.add(const _Vec3(0, 15.0, -14));
    final dorsalRear = vertices.length;
    vertices.add(const _Vec3(0, 8.0, -28));
    final ventralTip = vertices.length;
    vertices.add(const _Vec3(0, -9.5, -18));
    final ventralRear = vertices.length;
    vertices.add(const _Vec3(0, -4.5, -28));

    final faces = <_MeshFace>[];

    void addFan(
      int tip,
      List<int> ring, {
      double tone = 0.0,
      double emissive = 0.0,
    }) {
      for (var i = 0; i < ring.length; i++) {
        final next = (i + 1) % ring.length;
        faces.add(
          _MeshFace(
            <int>[tip, ring[i], ring[next]],
            tone: tone + (i.isEven ? 0.03 : -0.02),
            emissive: emissive,
            doubleSided: true,
          ),
        );
      }
    }

    void bridgeRings(
      List<int> front,
      List<int> back, {
      double tone = 0.0,
      bool glowDeck = false,
    }) {
      for (var i = 0; i < front.length; i++) {
        final next = (i + 1) % front.length;
        faces.add(
          _MeshFace(
            <int>[front[i], front[next], back[next], back[i]],
            tone: tone + (i == 0 || i == 1 ? 0.04 : -0.05),
            emissive: glowDeck && i == 0 ? 0.06 : (i.isEven ? 0.02 : 0),
            doubleSided: true,
          ),
        );
      }
    }

    addFan(0, ring1, tone: 0.1);
    bridgeRings(ring1, ring2, tone: 0.06, glowDeck: true); // Canopy glow
    bridgeRings(ring2, ring3, tone: 0.02);
    bridgeRings(ring3, ring4, tone: -0.05);
    addFan(
      aftCenter,
      <int>[ring4[3], ring4[2], ring4[1], ring4[0]],
      tone: -0.1,
      emissive: 0.08,
    ); // Engine exhaust glow map

    // Left Wing (Forward swept)
    faces.add(
      _MeshFace(
        <int>[ring2[0], ring3[0], leftTipTop],
        tone: 0.05,
        emissive: 0.02,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring2[3], leftTipBottom, ring3[3]],
        tone: -0.06,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring2[0], leftTipTop, leftTipBottom, ring2[3]],
        tone: -0.08,
        doubleSided: true,
      ),
    );

    // Left Weapon pod integration
    faces.add(
      _MeshFace(
        <int>[ring1[0], leftWeapon, ring2[0]],
        tone: 0.02,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring1[3], leftWeapon, ring2[3]],
        tone: -0.03,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[leftWeapon, leftTipTop, ring2[0]],
        tone: 0.04,
        doubleSided: true,
      ),
    );

    // Right Wing
    faces.add(
      _MeshFace(
        <int>[ring2[1], rightTipTop, ring3[1]],
        tone: 0.05,
        emissive: 0.02,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring2[2], ring3[2], rightTipBottom],
        tone: -0.06,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring2[1], ring2[2], rightTipBottom, rightTipTop],
        tone: -0.08,
        doubleSided: true,
      ),
    );

    // Right Weapon pod integration
    faces.add(
      _MeshFace(
        <int>[ring1[1], ring2[1], rightWeapon],
        tone: 0.02,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring1[2], ring2[2], rightWeapon],
        tone: -0.03,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[rightWeapon, ring2[1], rightTipTop],
        tone: 0.04,
        doubleSided: true,
      ),
    );

    // Engines and cowlings
    faces.add(
      _MeshFace(
        <int>[ring3[0], leftEngine, ring4[0]],
        tone: -0.12,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring3[3], ring4[3], leftEngine],
        tone: -0.14,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring3[1], ring4[1], rightEngine],
        tone: -0.12,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring3[2], rightEngine, ring4[2]],
        tone: -0.14,
        doubleSided: true,
      ),
    );

    // Dorsal stabilizer
    faces.add(
      _MeshFace(
        <int>[ring2[0], dorsalTip, ring2[1]],
        tone: 0.09,
        emissive: 0.03,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring2[0], ring3[0], dorsalRear, dorsalTip],
        tone: 0.07,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring3[1], ring2[1], dorsalTip, dorsalRear],
        tone: 0.07,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[dorsalTip, dorsalRear, ring4[0], ring4[1]],
        tone: 0.04,
        doubleSided: true,
      ),
    );

    // Ventral stabilizer
    faces.add(
      _MeshFace(
        <int>[ring2[3], ring2[2], ventralTip],
        tone: -0.12,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring3[3], ring2[3], ventralTip, ventralRear],
        tone: -0.1,
        doubleSided: true,
      ),
    );
    faces.add(
      _MeshFace(
        <int>[ring2[2], ring3[2], ventralRear, ventralTip],
        tone: -0.1,
        doubleSided: true,
      ),
    );

    return _MeshModel(vertices: vertices, faces: faces);
  }

  static _MeshModel _buildStationPodMesh() {
    final vertices = <_Vec3>[const _Vec3(0, 0, 36), const _Vec3(0, 0, -36)];

    List<int> addRing(double z, double xRadius, double yRadius) {
      final start = vertices.length;
      vertices.add(_Vec3(-xRadius, yRadius, z));
      vertices.add(_Vec3(xRadius, yRadius, z));
      vertices.add(_Vec3(xRadius, -yRadius, z));
      vertices.add(_Vec3(-xRadius, -yRadius, z));
      return <int>[start, start + 1, start + 2, start + 3];
    }

    final front = addRing(16, 10, 6);
    final mid = addRing(0, 12, 8);
    final rear = addRing(-18, 8, 5);
    final faces = <_MeshFace>[];

    void addFan(int tip, List<int> ring, double tone) {
      for (var i = 0; i < ring.length; i++) {
        final next = (i + 1) % ring.length;
        faces.add(
          _MeshFace(
            <int>[tip, ring[i], ring[next]],
            tone: tone + (i.isEven ? 0.02 : -0.01),
            doubleSided: true,
          ),
        );
      }
    }

    void bridge(List<int> a, List<int> b, double tone) {
      for (var i = 0; i < a.length; i++) {
        final next = (i + 1) % a.length;
        faces.add(
          _MeshFace(
            <int>[a[i], a[next], b[next], b[i]],
            tone: tone + (i < 2 ? 0.03 : -0.04),
            emissive: i == 0 || i == 1 ? 0.03 : 0,
            doubleSided: true,
          ),
        );
      }
    }

    addFan(0, front, 0.06);
    bridge(front, mid, 0.02);
    bridge(mid, rear, -0.03);
    addFan(1, <int>[rear[3], rear[2], rear[1], rear[0]], -0.08);
    faces.add(_MeshFace([front[0], front[1], mid[1], mid[0]], tone: 0.1));
    faces.add(
      _MeshFace(
        [rear[3], rear[2], mid[2], mid[3]],
        tone: -0.09,
        emissive: 0.05,
      ),
    );
    return _MeshModel(vertices: vertices, faces: faces);
  }

  static _MeshModel _buildStationMeshBastion() {
    return _MeshModel(
      vertices: [
        const _Vec3(0, 30, 0),
        const _Vec3(0, -30, 0),
        const _Vec3(0, 0, 36),
        const _Vec3(24, 0, 24),
        const _Vec3(34, 0, 0),
        const _Vec3(24, 0, -24),
        const _Vec3(0, 0, -36),
        const _Vec3(-24, 0, -24),
        const _Vec3(-34, 0, 0),
        const _Vec3(-24, 0, 24),
        const _Vec3(0, 12, 54),
        const _Vec3(0, -12, 54),
        const _Vec3(0, 12, -54),
        const _Vec3(0, -12, -54),
      ],
      faces: const [
        _MeshFace([0, 2, 3], tone: 0.06),
        _MeshFace([0, 3, 4], tone: 0.05),
        _MeshFace([0, 4, 5], tone: 0.04),
        _MeshFace([0, 5, 6], tone: 0.02),
        _MeshFace([0, 6, 7], tone: 0.04),
        _MeshFace([0, 7, 8], tone: 0.05),
        _MeshFace([0, 8, 9], tone: 0.04),
        _MeshFace([0, 9, 2], tone: 0.06),
        _MeshFace([1, 3, 2], tone: -0.08),
        _MeshFace([1, 4, 3], tone: -0.08),
        _MeshFace([1, 5, 4], tone: -0.1),
        _MeshFace([1, 6, 5], tone: -0.1),
        _MeshFace([1, 7, 6], tone: -0.08),
        _MeshFace([1, 8, 7], tone: -0.08),
        _MeshFace([1, 9, 8], tone: -0.1),
        _MeshFace([1, 2, 9], tone: -0.1),
        _MeshFace([2, 10, 11], tone: 0.15, emissive: 0.08),
        _MeshFace([2, 11, 3], tone: 0.04),
        _MeshFace([6, 5, 13], tone: -0.04),
        _MeshFace([6, 13, 12], tone: 0.02),
      ],
    );
  }

  static _MeshModel _buildStationMeshHalo() {
    const segments = 12;
    const outerR = 54.0;
    const innerR = 30.0;
    const topY = 8.0;
    const bottomY = -8.0;
    final vertices = <_Vec3>[
      const _Vec3(0, 18, 0),
      const _Vec3(0, -18, 0),
      const _Vec3(0, 0, 74),
      const _Vec3(0, 0, -74),
    ];
    for (var i = 0; i < segments; i++) {
      final a = (i / segments) * math.pi * 2;
      final c = math.cos(a);
      final s = math.sin(a);
      vertices.add(_Vec3(c * outerR, topY, s * outerR));
      vertices.add(_Vec3(c * outerR, bottomY, s * outerR));
      vertices.add(_Vec3(c * innerR, topY, s * innerR));
      vertices.add(_Vec3(c * innerR, bottomY, s * innerR));
    }

    final faces = <_MeshFace>[
      const _MeshFace([0, 2, 3], tone: 0.08, emissive: 0.06),
      const _MeshFace([1, 3, 2], tone: -0.08, emissive: 0.04),
    ];
    for (var i = 0; i < segments; i++) {
      final n = (i + 1) % segments;
      final ot0 = 4 + i * 4;
      final ob0 = 4 + i * 4 + 1;
      final it0 = 4 + i * 4 + 2;
      final ib0 = 4 + i * 4 + 3;
      final ot1 = 4 + n * 4;
      final ob1 = 4 + n * 4 + 1;
      final it1 = 4 + n * 4 + 2;
      final ib1 = 4 + n * 4 + 3;
      faces.add(_MeshFace([ot0, ot1, it1, it0], tone: 0.1, emissive: 0.05));
      faces.add(_MeshFace([ob1, ob0, ib0, ib1], tone: -0.09, emissive: 0.03));
      faces.add(_MeshFace([ot0, ob0, ob1, ot1], tone: -0.03));
      faces.add(_MeshFace([it1, ib1, ib0, it0], tone: -0.12));
    }
    return _MeshModel(vertices: vertices, faces: faces);
  }

  static _MeshModel _buildStationMeshSpire() {
    return _MeshModel(
      vertices: [
        const _Vec3(0, 8, 68),
        const _Vec3(-25, 5, 14),
        const _Vec3(25, 5, 14),
        const _Vec3(0, 25, -6),
        const _Vec3(0, -21, -9),
        const _Vec3(0, 2, -64),
        const _Vec3(-10, 0, -42),
        const _Vec3(10, 0, -42),
        const _Vec3(0, 36, -34),
        const _Vec3(0, -28, -32),
        const _Vec3(-30, -2, 26),
        const _Vec3(30, -2, 26),
      ],
      faces: const [
        _MeshFace([0, 1, 3], tone: 0.06),
        _MeshFace([0, 3, 2], tone: 0.08),
        _MeshFace([0, 4, 1], tone: -0.05),
        _MeshFace([0, 2, 4], tone: -0.02),
        _MeshFace([1, 10, 4], tone: -0.11),
        _MeshFace([2, 4, 11], tone: -0.1),
        _MeshFace([3, 8, 5], tone: 0.1, emissive: 0.04),
        _MeshFace([4, 5, 9], tone: -0.08),
        _MeshFace([3, 1, 5], tone: -0.06),
        _MeshFace([3, 5, 2], tone: -0.04),
        _MeshFace([4, 6, 5], tone: -0.12),
        _MeshFace([4, 5, 7], tone: -0.1),
      ],
    );
  }

  static _MeshModel _buildStationMeshCitadel() {
    const segments = 8;
    const radius = 30.0;
    const topY = 15.0;
    const bottomY = -15.0;

    final vertices = <_Vec3>[
      const _Vec3(0, 44, 0),
      const _Vec3(0, -44, 0),
      const _Vec3(0, 0, 84),
      const _Vec3(0, 0, -84),
      const _Vec3(84, 0, 0),
      const _Vec3(-84, 0, 0),
      const _Vec3(0, 0, 0),
    ];

    for (var i = 0; i < segments; i++) {
      final a = (i / segments) * math.pi * 2;
      final c = math.cos(a);
      final s = math.sin(a);
      vertices.add(_Vec3(c * radius, topY, s * radius));
      vertices.add(_Vec3(c * radius, bottomY, s * radius));
    }

    final faces = <_MeshFace>[];
    for (var i = 0; i < segments; i++) {
      final n = (i + 1) % segments;
      final top0 = 7 + i * 2;
      final bot0 = top0 + 1;
      final top1 = 7 + n * 2;
      final bot1 = top1 + 1;
      faces.add(_MeshFace([0, top1, top0], tone: 0.06));
      faces.add(_MeshFace([1, bot0, bot1], tone: -0.08));
      faces.add(_MeshFace([top0, top1, bot1, bot0], tone: -0.02));
    }

    faces.add(_MeshFace([6, 2, 0], tone: 0.12, emissive: 0.08));
    faces.add(_MeshFace([6, 1, 2], tone: -0.05, emissive: 0.04));
    faces.add(_MeshFace([6, 0, 3], tone: 0.09, emissive: 0.08));
    faces.add(_MeshFace([6, 3, 1], tone: -0.06, emissive: 0.04));
    faces.add(_MeshFace([6, 4, 0], tone: 0.1, emissive: 0.08));
    faces.add(_MeshFace([6, 1, 4], tone: -0.06, emissive: 0.04));
    faces.add(_MeshFace([6, 0, 5], tone: 0.1, emissive: 0.08));
    faces.add(_MeshFace([6, 5, 1], tone: -0.06, emissive: 0.04));

    faces.add(_MeshFace([2, 7, 9], tone: 0.04));
    faces.add(_MeshFace([2, 10, 8], tone: -0.01));
    faces.add(_MeshFace([3, 13, 11], tone: 0.04));
    faces.add(_MeshFace([3, 12, 14], tone: -0.01));
    faces.add(_MeshFace([4, 9, 11], tone: 0.04));
    faces.add(_MeshFace([4, 12, 10], tone: -0.01));
    faces.add(_MeshFace([5, 15, 13], tone: 0.04));
    faces.add(_MeshFace([5, 14, 16], tone: -0.01));

    return _MeshModel(vertices: vertices, faces: faces);
  }

  static _MeshModel _buildResourceCrystalMesh() {
    return _MeshModel(
      vertices: const <_Vec3>[
        _Vec3(0, 26, 0),
        _Vec3(0, -26, 0),
        _Vec3(0, 0, 22),
        _Vec3(0, 0, -22),
        _Vec3(-18, 0, 0),
        _Vec3(18, 0, 0),
        _Vec3(0, 8, 10),
        _Vec3(0, -6, -10),
      ],
      faces: const <_MeshFace>[
        _MeshFace([0, 2, 5], tone: 0.16, emissive: 0.08),
        _MeshFace([0, 4, 2], tone: 0.1, emissive: 0.06),
        _MeshFace([0, 3, 4], tone: 0.06, emissive: 0.04),
        _MeshFace([0, 5, 3], tone: 0.08, emissive: 0.04),
        _MeshFace([1, 5, 2], tone: -0.1, doubleSided: true),
        _MeshFace([1, 2, 4], tone: -0.08, doubleSided: true),
        _MeshFace([1, 4, 3], tone: -0.12, doubleSided: true),
        _MeshFace([1, 3, 5], tone: -0.1, doubleSided: true),
        _MeshFace([0, 6, 2], tone: 0.22, emissive: 0.1),
        _MeshFace([1, 3, 7], tone: -0.12, emissive: 0.04, doubleSided: true),
      ],
    );
  }

  static _MeshModel _buildPortalMesh() {
    const segments = 18;
    const outerR = 52.0;
    const innerR = 34.0;
    const halfDepth = 6.0;
    final vertices = <_Vec3>[];
    for (var i = 0; i < segments; i++) {
      final a = (i / segments) * math.pi * 2;
      final c = math.cos(a);
      final s = math.sin(a);
      vertices.add(_Vec3(c * outerR, s * outerR, -halfDepth));
      vertices.add(_Vec3(c * innerR, s * innerR, -halfDepth));
      vertices.add(_Vec3(c * outerR, s * outerR, halfDepth));
      vertices.add(_Vec3(c * innerR, s * innerR, halfDepth));
    }

    final faces = <_MeshFace>[];
    for (var i = 0; i < segments; i++) {
      final n = (i + 1) % segments;
      final fo0 = i * 4;
      final fi0 = i * 4 + 1;
      final bo0 = i * 4 + 2;
      final bi0 = i * 4 + 3;
      final fo1 = n * 4;
      final fi1 = n * 4 + 1;
      final bo1 = n * 4 + 2;
      final bi1 = n * 4 + 3;

      faces.add(
        _MeshFace(
          [fo0, fo1, fi1, fi0],
          tone: 0.06,
          emissive: 0.1,
          doubleSided: true,
        ),
      );
      faces.add(
        _MeshFace(
          [bo1, bo0, bi0, bi1],
          tone: -0.02,
          emissive: 0.08,
          doubleSided: true,
        ),
      );
      faces.add(
        _MeshFace(
          [fo0, bo0, bo1, fo1],
          tone: -0.04,
          emissive: 0.03,
          doubleSided: true,
        ),
      );
      faces.add(
        _MeshFace(
          [fi1, bi1, bi0, fi0],
          tone: -0.09,
          emissive: 0.02,
          doubleSided: true,
        ),
      );
    }

    return _MeshModel(vertices: vertices, faces: faces);
  }

  static _MeshModel _buildProjectileMesh() {
    return _MeshModel(
      vertices: const <_Vec3>[
        _Vec3(0, 0, 12),
        _Vec3(-1.5, 1.5, -4),
        _Vec3(1.5, 1.5, -4),
        _Vec3(1.5, -1.5, -4),
        _Vec3(-1.5, -1.5, -4),
        _Vec3(0, 0, -18),
      ],
      faces: const <_MeshFace>[
        _MeshFace([0, 1, 2], tone: 0.1, emissive: 0.8),
        _MeshFace([0, 2, 3], tone: 0.1, emissive: 0.8),
        _MeshFace([0, 3, 4], tone: 0.1, emissive: 0.8),
        _MeshFace([0, 4, 1], tone: 0.1, emissive: 0.8),
        _MeshFace([5, 2, 1], tone: -0.1, emissive: 0.4),
        _MeshFace([5, 3, 2], tone: -0.1, emissive: 0.4),
        _MeshFace([5, 4, 3], tone: -0.1, emissive: 0.4),
        _MeshFace([5, 1, 4], tone: -0.1, emissive: 0.4),
      ],
    );
  }

  static _MeshModel _buildBlastMesh() {
    final vertices = <_Vec3>[
      const _Vec3(0, 10, 0),
      const _Vec3(0, -10, 0),
      const _Vec3(10, 0, 0),
      const _Vec3(-10, 0, 0),
      const _Vec3(0, 0, 10),
      const _Vec3(0, 0, -10),
      const _Vec3(6, 6, 6),
      const _Vec3(-6, 6, 6),
      const _Vec3(6, -6, 6),
      const _Vec3(-6, -6, 6),
      const _Vec3(6, 6, -6),
      const _Vec3(-6, 6, -6),
      const _Vec3(6, -6, -6),
      const _Vec3(-6, -6, -6),
    ];
    final faces = <_MeshFace>[
      _MeshFace(const [0, 6, 4], emissive: 0.9, doubleSided: true),
      _MeshFace(const [0, 4, 7], emissive: 0.7, doubleSided: true),
      _MeshFace(const [0, 7, 3], emissive: 0.8, doubleSided: true),
      _MeshFace(const [0, 3, 11], emissive: 0.6, doubleSided: true),
      _MeshFace(const [0, 11, 5], emissive: 0.9, doubleSided: true),
      _MeshFace(const [0, 5, 10], emissive: 0.7, doubleSided: true),
      _MeshFace(const [0, 10, 2], emissive: 0.8, doubleSided: true),
      _MeshFace(const [0, 2, 6], emissive: 0.6, doubleSided: true),
      _MeshFace(const [1, 8, 4], emissive: 0.8, doubleSided: true),
      _MeshFace(const [1, 4, 9], emissive: 0.6, doubleSided: true),
      _MeshFace(const [1, 9, 3], emissive: 0.9, doubleSided: true),
      _MeshFace(const [1, 3, 13], emissive: 0.7, doubleSided: true),
      _MeshFace(const [1, 13, 5], emissive: 0.8, doubleSided: true),
      _MeshFace(const [1, 5, 12], emissive: 0.6, doubleSided: true),
      _MeshFace(const [1, 12, 2], emissive: 0.9, doubleSided: true),
      _MeshFace(const [1, 2, 8], emissive: 0.7, doubleSided: true),
    ];
    return _MeshModel(vertices: vertices, faces: faces);
  }

  static _MeshModel _buildCharacterMesh() {
    return _MeshModel(
      vertices: const <_Vec3>[
        _Vec3(0, 8, 4), // 0: Top head
        _Vec3(-4, 4, 6), // 1: Forehead left
        _Vec3(4, 4, 6), // 2: Forehead right
        _Vec3(-3, -1, 7), // 3: Cheek left
        _Vec3(3, -1, 7), // 4: Cheek right
        _Vec3(0, -4, 8), // 5: Chin/jaw
        _Vec3(-5, 3, 0), // 6: Ear left
        _Vec3(5, 3, 0), // 7: Ear right
        _Vec3(0, 6, -5), // 8: Back head
        _Vec3(0, -5, 2), // 9: Neck lower
        _Vec3(-12, -8, 0), // 10: Shoulder left
        _Vec3(12, -8, 0), // 11: Shoulder right
        _Vec3(-16, -18, -2), // 12: Chest left down
        _Vec3(16, -18, -2), // 13: Chest right down
        _Vec3(0, -18, 5), // 14: Chest center down
        _Vec3(0, -8, 6), // 15: Chest upper center
      ],
      faces: const <_MeshFace>[
        // Face/Helmet
        _MeshFace([0, 1, 2], tone: 0.1, emissive: 0.05),
        _MeshFace([1, 3, 5, 4, 2], tone: 0.05, emissive: 0.1), // Visor area
        _MeshFace([0, 6, 1], tone: 0.02),
        _MeshFace([0, 2, 7], tone: 0.02),
        _MeshFace([1, 6, 3], tone: -0.05),
        _MeshFace([2, 4, 7], tone: -0.05),
        _MeshFace([3, 9, 5], tone: -0.08),
        _MeshFace([4, 5, 9], tone: -0.08),

        // Back head
        _MeshFace([0, 8, 6], tone: 0.0),
        _MeshFace([0, 7, 8], tone: 0.0),
        _MeshFace([6, 8, 9, 3], tone: -0.06),
        _MeshFace([7, 4, 9, 8], tone: -0.06),

        // Shoulders & Chest
        _MeshFace([9, 10, 15], tone: 0.06),
        _MeshFace([9, 15, 11], tone: 0.06),
        _MeshFace([10, 12, 14, 15], tone: 0.02),
        _MeshFace([11, 15, 14, 13], tone: 0.02),

        // Back
        _MeshFace([9, 11, 13, 14, 12, 10], tone: -0.1, doubleSided: true),
      ],
    );
  }

  void _drawLabel(Canvas canvas, Offset pos, String text, Color color) {
    final compact = pos.dx < 240;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Color.lerp(
            color,
            const Color(0xFFE5D089),
            0.35,
          )!.withValues(alpha: 0.95),
          fontSize: compact ? 5.2 : 9.4,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          fontFamilyFallback: const ['Menlo', 'Monaco', 'Courier New'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 220);
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant Sector3DPainter oldDelegate) => true;
}

class _ProjectedPoint {
  const _ProjectedPoint(this.screen, this.depth, this.scale);

  final Offset screen;
  final double depth;
  final double scale;
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);

  static const _Vec3 zero = _Vec3(0, 0, 0);

  final double x;
  final double y;
  final double z;

  _Vec3 operator +(_Vec3 other) => _Vec3(x + other.x, y + other.y, z + other.z);
  _Vec3 operator -(_Vec3 other) => _Vec3(x - other.x, y - other.y, z - other.z);
  _Vec3 operator -() => _Vec3(-x, -y, -z);
  _Vec3 operator *(double scalar) => _Vec3(x * scalar, y * scalar, z * scalar);
  _Vec3 operator /(double scalar) => _Vec3(x / scalar, y / scalar, z / scalar);

  double dot(_Vec3 other) => x * other.x + y * other.y + z * other.z;

  _Vec3 cross(_Vec3 other) => _Vec3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  double get length => math.sqrt(x * x + y * y + z * z);

  _Vec3 normalized() {
    final len = length;
    if (len <= 0.000001) {
      return this;
    }
    return this / len;
  }
}

class _MeshModel {
  const _MeshModel({required this.vertices, required this.faces});

  final List<_Vec3> vertices;
  final List<_MeshFace> faces;
}

class _MeshFace {
  const _MeshFace(
    this.indices, {
    this.tone = 0,
    this.emissive = 0,
    this.doubleSided = false,
  });

  final List<int> indices;
  final double tone;
  final double emissive;
  final bool doubleSided;
}

class _MeshTriangle {
  const _MeshTriangle({
    required this.points,
    required this.depth,
    required this.fill,
    required this.stroke,
  });

  final List<Offset> points;
  final double depth;
  final Color fill;
  final Color stroke;
}

class _TargetSnapshot {
  const _TargetSnapshot({
    required this.pirate,
    required this.projection,
    required this.score,
    required this.distance,
    required this.isTracked,
    required this.isOnScreen,
  });

  final PirateShip pirate;
  final _ProjectedPoint projection;
  final double score;
  final double distance;
  final bool isTracked;
  final bool isOnScreen;
}

class GalaxyMapPainter extends CustomPainter {
  GalaxyMapPainter(this.game);

  final VanSoleGame game;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final area = rect.deflate(6);
    final sectors = game.sectorLayouts;
    if (sectors.isEmpty) {
      return;
    }

    final cellWidth = area.width / sectors.length;
    final activeContract = game.activeContract;
    final pickupSector = activeContract?.pickup.sectorIndex;
    final destinationSector = activeContract?.destination.sectorIndex;

    final linkPaint = Paint()
      ..color = const Color(0xFFA78BFA).withValues(alpha: 0.25)
      ..strokeWidth = 1.5;
    for (var i = 0; i < sectors.length; i++) {
      final sector = sectors[i];
      final fromCenter = Offset(
        area.left + cellWidth * i + cellWidth / 2,
        area.top + 22,
      );
      for (final portal in sector.portals) {
        final j = portal.targetSectorIndex;
        if (j <= i || j >= sectors.length) {
          continue;
        }
        final toCenter = Offset(
          area.left + cellWidth * j + cellWidth / 2,
          area.top + 22,
        );
        canvas.drawLine(fromCenter, toCenter, linkPaint);
      }
    }

    for (var i = 0; i < sectors.length; i++) {
      final sector = sectors[i];
      final cellRect = Rect.fromLTWH(
        area.left + i * cellWidth + 4,
        area.top + 8,
        cellWidth - 8,
        area.height - 16,
      );
      final isCurrent = game.sectorIndex == i;
      final isPickup = pickupSector == i;
      final isDest = destinationSector == i;

      canvas.drawRRect(
        RRect.fromRectAndRadius(cellRect, const Radius.circular(12)),
        Paint()
          ..color =
              (isCurrent ? const Color(0xFF102235) : const Color(0xFF0B131E))
                  .withValues(alpha: 0.95),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(cellRect, const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color =
              (isCurrent
                      ? const Color(0xFF34E7C5)
                      : (isPickup || isDest)
                      ? const Color(0xFFFBBF24)
                      : Colors.white)
                  .withValues(alpha: isCurrent ? 0.45 : 0.12),
      );

      final titlePainter = TextPainter(
        text: TextSpan(
          text: sector.name,
          style: TextStyle(
            color: isCurrent ? const Color(0xFF34E7C5) : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: cellRect.width - 12);
      titlePainter.paint(canvas, Offset(cellRect.left + 6, cellRect.top + 4));

      final mini = Rect.fromLTWH(
        cellRect.left + 8,
        cellRect.top + 22,
        cellRect.width - 16,
        cellRect.height - 30,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(mini, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: 0.06),
      );

      for (final station in sector.stations) {
        final p = _miniPoint(mini, station.position);
        canvas.drawCircle(
          p,
          2.4,
          Paint()..color = station.color.withValues(alpha: 0.9),
        );
        if (activeContract != null &&
            (activeContract.pickup.id == station.id ||
                activeContract.destination.id == station.id)) {
          canvas.drawCircle(
            p,
            4.2,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color =
                  (activeContract.pickup.id == station.id
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF4ADE80))
                      .withValues(alpha: 0.8),
          );
        }
      }

      for (final portal in sector.portals) {
        final p = _miniPoint(mini, portal.position);
        canvas.drawCircle(
          p,
          3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = portal.color.withValues(
              alpha: game.jumpCandidate?.id == portal.id ? 0.95 : 0.65,
            ),
        );
      }

      if (isPickup || isDest) {
        final label = isPickup && isDest
            ? 'P/D'
            : isPickup
            ? 'P'
            : 'D';
        final badge = Rect.fromLTWH(
          cellRect.right - 26,
          cellRect.top + 4,
          20,
          14,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(badge, const Radius.circular(7)),
          Paint()
            ..color =
                (isPickup ? const Color(0xFFFBBF24) : const Color(0xFF4ADE80))
                    .withValues(alpha: 0.25),
        );
        final badgeText = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        badgeText.paint(
          canvas,
          Offset(
            badge.center.dx - badgeText.width / 2,
            badge.center.dy - badgeText.height / 2,
          ),
        );
      }
    }
  }

  Offset _miniPoint(Rect rect, Offset world) {
    final x = rect.left + (world.dx / VanSoleGame.worldWidth) * rect.width;
    final y = rect.top + (world.dy / VanSoleGame.worldHeight) * rect.height;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant GalaxyMapPainter oldDelegate) => true;
}

class RadarPainter extends CustomPainter {
  RadarPainter(this.game);

  final VanSoleGame game;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2 - 8;

    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF08101A));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF34E7C5).withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    for (final fraction in [0.33, 0.66]) {
      canvas.drawCircle(
        center,
        radius * fraction,
        Paint()
          ..color = const Color(0xFF34E7C5).withValues(alpha: 0.10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );

    Offset radarPoint(Offset worldPoint) {
      final delta = worldPoint - game.playerPosition;
      final scaled = delta / VanSoleGame.radarRange;
      final clampedLen = math.min(1.0, scaled.distance);
      final dir = scaled == Offset.zero ? Offset.zero : _normalize(scaled);
      final p = dir * (clampedLen * radius);
      return center + p;
    }

    for (final station in game.stations) {
      final p = radarPoint(station.position);
      final isNear = game.nearestStation?.id == station.id;
      canvas.drawCircle(
        p,
        isNear ? 4 : 3,
        Paint()..color = station.color.withValues(alpha: isNear ? 0.95 : 0.8),
      );
    }
    for (final portal in game.portals) {
      final p = radarPoint(portal.position);
      final isCandidate = game.jumpCandidate?.id == portal.id;
      canvas.drawCircle(
        p,
        isCandidate ? 4 : 3,
        Paint()
          ..color = portal.color.withValues(alpha: isCandidate ? 0.98 : 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isCandidate ? 1.8 : 1.2,
      );
    }
    for (final pirate in game.pirates) {
      final p = radarPoint(pirate.position);
      canvas.drawCircle(
        p,
        2.5,
        Paint()..color = const Color(0xFFF87171).withValues(alpha: 0.9),
      );
    }

    final nose =
        center +
        Offset(math.cos(game.playerFacing), math.sin(game.playerFacing)) * 12;
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFF34E7C5));
    canvas.drawLine(
      center,
      nose,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) => true;
}

double _clamp(num value, double min, double max) =>
    value.clamp(min, max).toDouble();

Offset _normalize(Offset value) {
  final d = value.distance;
  if (d == 0) {
    return Offset.zero;
  }
  return value / d;
}

double _approachAngle(double current, double target, double maxStep) {
  var delta = (target - current + math.pi) % (2 * math.pi) - math.pi;
  if (delta.abs() <= maxStep) {
    return target;
  }
  delta = delta.sign * maxStep;
  return current + delta;
}
