import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/common/http.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/correspondence/correspondence_service.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/model/notifications/notification_service.dart';
import 'package:lichess_mobile/src/model/notifications/notifications.dart';
import 'package:mocktail/mocktail.dart';
import '../../binding.dart';
import '../../test_container.dart';
import '../../test_utils.dart';
import '../auth/fake_session_storage.dart';

class NotificationDisplayMock extends Mock
    implements FlutterLocalNotificationsPlugin {}

class CorrespondenceServiceMock extends Mock implements CorrespondenceService {}

class FakePlayableGame extends Fake implements PlayableGame {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final notificationDisplayMock = NotificationDisplayMock();
  final correspondenceServiceMock = CorrespondenceServiceMock();

  int registerDeviceCalls = 0;

  setUpAll(() {
    registerFallbackValue(FakePlayableGame());
  });

  tearDown(() {
    registerDeviceCalls = 0;
    reset(notificationDisplayMock);
    reset(correspondenceServiceMock);
  });

  final registerMockClient = MockClient((request) {
    if (request.url.path == '/mobile/register/firebase/test-token') {
      registerDeviceCalls++;
      return mockResponse('{"ok": true}', 200);
    }
    return mockResponse('', 404);
  });

  group('Start service:', () {
    test('request permissions', () async {
      final container = await makeContainer();

      final notificationService = container.read(notificationServiceProvider);

      await notificationService.start();

      final calls =
          testBinding.firebaseMessaging.verifyRequestPermissionCalls();
      expect(calls, hasLength(1));
      expect(
        calls.first,
        equals(
          (
            alert: true,
            badge: true,
            sound: true,
            announcement: false,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
          ),
        ),
      );
    });

    test(
        'register device when online, token exists and permissions are granted and a session exists',
        () async {
      final container = await makeContainer(
        userSession: fakeSession,
        overrides: [
          lichessClientProvider.overrideWith(
            (ref) => LichessClient(registerMockClient, ref),
          ),
        ],
      );

      final notificationService = container.read(notificationServiceProvider);

      FakeAsync().run((async) {
        notificationService.start();

        async.flushMicrotasks();

        expect(registerDeviceCalls, 1);
      });
    });

    test("don't try to register device when permissions are not granted",
        () async {
      final container = await makeContainer(
        userSession: fakeSession,
        overrides: [
          lichessClientProvider.overrideWith(
            (ref) => LichessClient(registerMockClient, ref),
          ),
        ],
      );

      final notificationService = container.read(notificationServiceProvider);

      FakeAsync().run((async) {
        testBinding.firebaseMessaging.willGrantPermission = false;

        notificationService.start();

        async.flushMicrotasks();

        expect(registerDeviceCalls, 0);
      });
    });

    test("don't try to register device when user is not logged in", () async {
      final container = await makeContainer(
        overrides: [
          lichessClientProvider.overrideWith(
            (ref) => LichessClient(registerMockClient, ref),
          ),
        ],
      );

      final notificationService = container.read(notificationServiceProvider);

      FakeAsync().run((async) {
        notificationService.start();

        async.flushMicrotasks();

        expect(registerDeviceCalls, 0);
      });
    });
  });

  group('Correspondence game update notifications', () {
    test('FCM message with associated notification will show it in foreground',
        () async {
      final container = await makeContainer(
        userSession: fakeSession,
        overrides: [
          lichessClientProvider.overrideWith(
            (ref) => LichessClient(registerMockClient, ref),
          ),
          notificationDisplayProvider
              .overrideWith((_) => notificationDisplayMock),
        ],
      );

      final notificationService = container.read(notificationServiceProvider);

      const fullId = GameFullId('9wlmxmibr9gh');

      when(
        () => notificationDisplayMock.show(
          any(),
          any(),
          any(),
          any(),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) => Future.value());

      FakeAsync().run((async) {
        notificationService.start();

        async.flushMicrotasks();

        testBinding.firebaseMessaging.onMessage.add(
          const RemoteMessage(
            data: {
              'lichess.type': 'gameMove',
              'lichess.fullId': '9wlmxmibr9gh',
            },
            notification: RemoteNotification(
              title: 'It is your turn!',
              body: 'Dr-Alaakour played a move',
            ),
          ),
        );

        async.flushMicrotasks();

        const expectedNotif = CorresGameUpdateNotification(
          fullId,
          'It is your turn!',
          'Dr-Alaakour played a move',
        );

        final result = verify(
          () => notificationDisplayMock.show(
            fullId.hashCode,
            'It is your turn!',
            'Dr-Alaakour played a move',
            captureAny(),
            payload: jsonEncode(expectedNotif.payload),
          ),
        );

        result.called(1);
        expect(
          result.captured[0],
          isA<NotificationDetails>()
              .having(
                (d) => d.android?.importance,
                'importance',
                Importance.high,
              )
              .having(
                (d) => d.android?.priority,
                'priority',
                Priority.defaultPriority,
              ),
        );
      });
    });

    test('FCM game data message will update the game', () async {
      final container = await makeContainer(
        userSession: fakeSession,
        overrides: [
          lichessClientProvider.overrideWith(
            (ref) => LichessClient(registerMockClient, ref),
          ),
          notificationDisplayProvider
              .overrideWith((_) => notificationDisplayMock),
          correspondenceServiceProvider
              .overrideWith((_) => correspondenceServiceMock),
        ],
      );

      final notificationService = container.read(notificationServiceProvider);

      const fullId = GameFullId('Fn9UvVKFsopx');

      when(
        () => correspondenceServiceMock.onServerUpdateEvent(
          fullId,
          any(that: isA<PlayableGame>()),
          fromBackground: false,
        ),
      ).thenAnswer((_) => Future.value());

      when(
        () => notificationDisplayMock.show(
          any(),
          any(),
          any(),
          any(),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) => Future.value());

      FakeAsync().run((async) {
        notificationService.start();

        async.flushMicrotasks();

        testBinding.firebaseMessaging.onMessage.add(
          const RemoteMessage(
            data: {
              'lichess.type': 'gameMove',
              'lichess.fullId': 'Fn9UvVKFsopx',
              'lichess.round':
                  '{"game":{"id":"Fn9UvVKF","variant":{"key":"standard","name":"Standard","short":"Std"},"speed":"bullet","perf":"bullet","rated":true,"fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","turns":0,"source":"lobby","status":{"id":20,"name":"started"},"createdAt":1706204482969,"pgn":""},"white":{"user":{"name":"chabrot","id":"chabrot"},"rating":1801},"black":{"user":{"name":"veloce","id":"veloce"},"rating":1798},"socket":0,"expiration":{"idleMillis":67,"millisToMove":20000},"clock":{"running":false,"initial":120,"increment":1,"white":120,"black":120,"emerg":15,"moretime":15},"takebackable":true,"youAre":"black","prefs":{"autoQueen":2,"zen":2,"confirmResign":true,"enablePremove":true},"chat":{"lines":[]}}',
            },
            notification: RemoteNotification(
              title: 'It is your turn!',
              body: 'Dr-Alaakour played a move',
            ),
          ),
        );

        async.flushMicrotasks();

        verify(
          () => correspondenceServiceMock.onServerUpdateEvent(
            fullId,
            any(that: isA<PlayableGame>()),
            fromBackground: false,
          ),
        ).called(1);

        verify(
          () => notificationDisplayMock.show(
            any(),
            any(),
            any(),
            any(),
            payload: any(named: 'payload'),
          ),
        ).called(1);
      });
    });

    test('FCM game data message without notification', () async {
      final container = await makeContainer(
        userSession: fakeSession,
        overrides: [
          lichessClientProvider.overrideWith(
            (ref) => LichessClient(registerMockClient, ref),
          ),
          notificationDisplayProvider
              .overrideWith((_) => notificationDisplayMock),
          correspondenceServiceProvider
              .overrideWith((_) => correspondenceServiceMock),
        ],
      );

      final notificationService = container.read(notificationServiceProvider);

      when(
        () => correspondenceServiceMock.onServerUpdateEvent(
          any(that: isA<GameFullId>()),
          any(that: isA<PlayableGame>()),
          fromBackground: false,
        ),
      ).thenAnswer((_) => Future.value());

      FakeAsync().run((async) {
        notificationService.start();

        async.flushMicrotasks();

        testBinding.firebaseMessaging.onMessage.add(
          const RemoteMessage(
            data: {
              'lichess.type': 'gameMove',
              'lichess.fullId': 'Fn9UvVKFsopx',
              'lichess.round':
                  '{"game":{"id":"Fn9UvVKF","variant":{"key":"standard","name":"Standard","short":"Std"},"speed":"bullet","perf":"bullet","rated":true,"fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","turns":0,"source":"lobby","status":{"id":20,"name":"started"},"createdAt":1706204482969,"pgn":""},"white":{"user":{"name":"chabrot","id":"chabrot"},"rating":1801},"black":{"user":{"name":"veloce","id":"veloce"},"rating":1798},"socket":0,"expiration":{"idleMillis":67,"millisToMove":20000},"clock":{"running":false,"initial":120,"increment":1,"white":120,"black":120,"emerg":15,"moretime":15},"takebackable":true,"youAre":"black","prefs":{"autoQueen":2,"zen":2,"confirmResign":true,"enablePremove":true},"chat":{"lines":[]}}',
            },
          ),
        );

        async.flushMicrotasks();

        verify(
          () => correspondenceServiceMock.onServerUpdateEvent(
            any(that: isA<GameFullId>()),
            any(that: isA<PlayableGame>()),
            fromBackground: false,
          ),
        ).called(1);

        verifyNever(
          () => notificationDisplayMock.show(
            any(),
            any(),
            any(),
            any(),
            payload: any(named: 'payload'),
          ),
        );
      });
    });
  });
}
