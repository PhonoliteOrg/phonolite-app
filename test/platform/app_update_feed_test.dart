import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';
import 'package:phonolite_app/data/models/updates/app_update_release.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_feed.dart';

const _configuration = AppUpdateConfiguration(
  available: true,
  feedUrl: 'https://github.com/PhonoliteOrg/phonolite-app/releases/latest/download/windows-appcast.xml',
  currentVersion: '0.2.0.0',
);

String _item(String version, {String os = 'windows-x64', String scheme = 'https'}) =>
    '''
<item><sparkle:version>$version</sparkle:version>
<enclosure url="$scheme://github.com/PhonoliteOrg/phonolite-app/releases/download/v$version/setup.exe"
sparkle:os="$os"/></item>''';

String _appcast(List<String> items) => '''
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel>${items.join()}</channel></rss>''';

void main() {
  test('selects the numerically newest Windows release regardless of feed ordering', () {
    final release = AppUpdateRelease.latestFromAppcast(
      _appcast([
        _item('0.2.3.0'),
        _item('0.2.10.2'),
        _item('9.0.0.0', os: 'macos'),
        _item('8.0.0.0', os: 'windows-arm64'),
        _item('7.0.0.0', scheme: 'http'),
        _item('0.2.1.0'),
        _item('not-a-version'),
      ]),
      currentVersion: '0.2.0.0',
    );
    expect(release?.version, '0.2.10.2');
  });

  test('equal and older releases do not offer updates or downgrades', () {
    expect(
      AppUpdateRelease.latestFromAppcast(_appcast([_item('0.2.0.0'), _item('0.1.99.0')]), currentVersion: '0.2.0.0'),
      isNull,
    );
    expect(const AppUpdateRelease(version: '0.2.1.0').displayVersion, '0.2.1');
  });

  test('rejects non-appcast content and invalid running versions', () {
    expect(() => AppUpdateRelease.latestFromAppcast('<html/>', currentVersion: '0.2.0.0'), throwsFormatException);
    expect(() => AppUpdateRelease.latestFromAppcast(_appcast([]), currentVersion: 'unknown'), throwsFormatException);
  });

  test('follows GitHub HTTPS asset redirects with no credentials or server authentication', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (requests.length == 1) {
        return http.Response(
          '',
          302,
          headers: {'location': 'https://release-assets.githubusercontent.com/appcast.xml'},
        );
      }
      return http.Response(_appcast([_item('0.2.1.0')]), 200);
    });
    final feed = HttpAppUpdateFeed(createClient: () => client);
    final release = await feed.latest(_configuration);
    expect(release?.version, '0.2.1.0');
    expect(requests.map((request) => request.url.host), ['github.com', 'release-assets.githubusercontent.com']);
    expect(requests.every((request) => !request.headers.containsKey('authorization')), isTrue);
    expect(requests.every((request) => !request.followRedirects), isTrue);
    feed.close();
  });

  test('rejects an HTTPS redirect to HTTP before contacting the insecure URL', () async {
    var requests = 0;
    final feed = HttpAppUpdateFeed(
      createClient: () => MockClient((_) async {
        requests++;
        return http.Response('', 302, headers: {'location': 'http://example.com/appcast.xml'});
      }),
    );
    await expectLater(feed.latest(_configuration), throwsFormatException);
    expect(requests, 1);
    feed.close();
  });

  test('a missing initial GitHub release is a failed check rather than up to date', () async {
    final feed = HttpAppUpdateFeed(createClient: () => MockClient((_) async => http.Response('Not Found', 404)));
    await expectLater(feed.latest(_configuration), throwsA(isA<http.ClientException>()));
    feed.close();
  });

  test('bounds feed size and redirect loops', () async {
    final oversized = HttpAppUpdateFeed(
      createClient: () => MockClient((_) async => http.Response('x' * (1024 * 1024 + 1), 200)),
    );
    await expectLater(oversized.latest(_configuration), throwsFormatException);
    oversized.close();
    var redirects = 0;
    final loop = HttpAppUpdateFeed(
      createClient: () => MockClient((_) async {
        redirects++;
        return http.Response('', 302, headers: {'location': _configuration.feedUrl});
      }),
    );
    await expectLater(loop.latest(_configuration), throwsFormatException);
    expect(redirects, 6);
    loop.close();
  });
}
