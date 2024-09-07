import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/broadcast/broadcast.dart';
import 'package:lichess_mobile/src/model/broadcast/broadcast_providers.dart';
import 'package:lichess_mobile/src/model/broadcast/broadcast_repository.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/socket.dart';
import 'package:lichess_mobile/src/utils/json.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'broadcast_round_controller.g.dart';

@riverpod
class BroadcastRoundController extends _$BroadcastRoundController {
  static Uri broadcastSocketUri(BroadcastRoundId broadcastRoundId) =>
      Uri(path: 'study/$broadcastRoundId/socket/v6');

  StreamSubscription<SocketEvent>? _subscription;

  Timer? _timer;

  late SocketClient _socketClient;

  @override
  Future<BroadcastRoundGames> build(BroadcastRoundId broadcastRoundId) async {
    _socketClient = ref
        .watch(socketPoolProvider)
        .open(BroadcastRoundController.broadcastSocketUri(broadcastRoundId));

    _subscription = _socketClient.stream.listen(_handleSocketEvent);

    ref.onDispose(() {
      _subscription?.cancel();
      _timer?.cancel();
    });

    final games =
        await ref.watch(broadcastRoundProvider(broadcastRoundId).future);

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClocks(),
    );

    return games;
  }

  void _updateClocks() {
    state = AsyncData(
      state.requireValue.map((gameId, game) {
        if (!game.isPlaying) return MapEntry(gameId, game);
        final thinkTime = game.thinkTime;
        final newThinkTime = thinkTime + const Duration(seconds: 1);
        return MapEntry(gameId, game.copyWith(thinkTime: newThinkTime));
      }),
    );
  }

  void _handleSocketEvent(SocketEvent event) {
    if (!state.hasValue) return;

    switch (event.topic) {
      // Sent when a node is recevied from the broadcast
      case 'addNode':
        _handleAddNodeEvent(event);
      // Sent when the state of games changes
      case 'chapters':
        _handleChaptersEvent(event);
      // Sent when clocks are updated from the broadcast
      case 'clock':
        _handleClockEvent(event);
    }
  }

  void _handleAddNodeEvent(SocketEvent event) {
    // The path of the last and current move of the broadcasted game
    // Its value is "!" if the path is identical to one of the node that was received
    final currentPath = pick(event.data, 'relayPath').asUciPathOrThrow();

    // We check that the event we received is for the last move of the game
    if (currentPath.value != '!') return;

    final broadcastGameId =
        pick(event.data, 'p', 'chapterId').asBroadcastGameIdOrThrow();

    final fen = pick(event.data, 'n', 'fen').asStringOrThrow();

    final playingSide = Setup.parseFen(fen).turn;

    state = AsyncData(
      state.requireValue.update(
        broadcastGameId,
        (broadcastGame) => broadcastGame.copyWith(
          players: IMap(
            {
              playingSide: broadcastGame.players[playingSide]!,
              playingSide.opposite:
                  broadcastGame.players[playingSide.opposite]!.copyWith(
                clock: pick(event.data, 'n', 'clock')
                    .asDurationFromCentiSecondsOrNull(),
              ),
            },
          ),
          fen: fen,
          lastMove: pick(event.data, 'n', 'uci').asUciMoveOrThrow(),
          thinkTime: Duration.zero,
        ),
      ),
    );
  }

  void _handleChaptersEvent(SocketEvent event) {
    final games = pick(event.data).asListOrThrow(gameFromPick);
    state = AsyncData(IMap.fromEntries(games));
  }

  void _handleClockEvent(SocketEvent event) {
    final broadcastGameId =
        pick(event.data, 'p', 'chapterId').asBroadcastGameIdOrThrow();
    final whiteClock = pick(event.data, 'p', 'relayClocks', 0)
        .asDurationFromCentiSecondsOrNull();
    final blackClock = pick(event.data, 'p', 'relayClocks', 1)
        .asDurationFromCentiSecondsOrNull();
    state = AsyncData(
      state.requireValue.update(
        broadcastGameId,
        (broadcastsGame) => broadcastsGame.copyWith(
          players: IMap(
            {
              Side.white: broadcastsGame.players[Side.white]!.copyWith(
                clock: whiteClock,
              ),
              Side.black: broadcastsGame.players[Side.black]!.copyWith(
                clock: blackClock,
              ),
            },
          ),
        ),
      ),
    );
  }
}
