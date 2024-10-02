import 'dart:math' as math;
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/settings/board_theme_screen.dart';
import 'package:lichess_mobile/src/view/settings/piece_set_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform_scaffold.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';

class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: const PlatformAppBar(title: Text('Theme')),
      body: _Body(),
    );
  }
}

String shapeColorL10n(
  BuildContext context,
  ShapeColor shapeColor,
) =>
    // TODO add l10n
    switch (shapeColor) {
      ShapeColor.green => 'Green',
      ShapeColor.red => 'Red',
      ShapeColor.blue => 'Blue',
      ShapeColor.yellow => 'Yellow',
    };

class _Body extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardPrefs = ref.watch(boardPreferencesProvider);

    const horizontalPadding = 52.0;

    return SafeArea(
      child: ListView(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final double boardSize = math.min(
                290,
                constraints.biggest.shortestSide - horizontalPadding * 2,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 16,
                ),
                child: Center(
                  child: Chessboard.fixed(
                    size: boardSize,
                    orientation: Side.white,
                    lastMove: const NormalMove(from: Square.e2, to: Square.e4),
                    fen:
                        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
                    shapes: <Shape>{
                      Circle(
                        color: boardPrefs.shapeColor.color,
                        orig: Square.fromName('b8'),
                      ),
                      Arrow(
                        color: boardPrefs.shapeColor.color,
                        orig: Square.fromName('b8'),
                        dest: Square.fromName('c6'),
                      ),
                    }.lock,
                    settings: ChessboardSettings(
                      enableCoordinates: false,
                      borderRadius:
                          const BorderRadius.all(Radius.circular(4.0)),
                      boxShadow: boardShadows,
                      pieceAssets: boardPrefs.pieceSet.assets,
                      colorScheme: boardPrefs.boardTheme.colors,
                    ),
                  ),
                ),
              );
            },
          ),
          ListSection(
            hasLeading: true,
            children: [
              SettingsListTile(
                icon: const Icon(LichessIcons.chess_board),
                settingsLabel: Text(context.l10n.board),
                settingsValue: boardPrefs.boardTheme.label,
                onTap: () {
                  pushPlatformRoute(
                    context,
                    title: context.l10n.board,
                    builder: (context) => const BoardThemeScreen(),
                  );
                },
              ),
              SettingsListTile(
                icon: const Icon(LichessIcons.chess_pawn),
                settingsLabel: Text(context.l10n.pieceSet),
                settingsValue: boardPrefs.pieceSet.label,
                onTap: () {
                  pushPlatformRoute(
                    context,
                    title: context.l10n.pieceSet,
                    builder: (context) => const PieceSetScreen(),
                  );
                },
              ),
              SettingsListTile(
                icon: const Icon(LichessIcons.arrow_full_upperright),
                settingsLabel: const Text('Shape color'),
                settingsValue: shapeColorL10n(context, boardPrefs.shapeColor),
                onTap: () {
                  showChoicePicker(
                    context,
                    choices: ShapeColor.values,
                    selectedItem: boardPrefs.shapeColor,
                    labelBuilder: (t) => Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: shapeColorL10n(context, t),
                          ),
                          const TextSpan(text: '   '),
                          WidgetSpan(
                            child: Container(
                              width: 15,
                              height: 15,
                              color: t.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    onSelectedItemChanged: (ShapeColor? value) {
                      ref
                          .read(boardPreferencesProvider.notifier)
                          .setShapeColor(value ?? ShapeColor.green);
                    },
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
