import 'package:flutter_test/flutter_test.dart';
import 'package:shitreed_customer/alani/alani_embeds.dart';

void main() {
  test('public YouTube URL converts to official no-cookie embedded player', () {
    final value = alaniOfficialEmbed(
      Uri.parse('https://www.youtube.com/watch?v=abcdefghijk'));
    expect(value?.host, 'www.youtube-nocookie.com');
    expect(value?.path, '/embed/abcdefghijk');
  });

  test('TikTok video post converts to official embeddable player', () {
    final value = alaniOfficialEmbed(
      Uri.parse('https://www.tiktok.com/@author/video/6718335390845095173'));
    expect(value?.host, 'www.tiktok.com');
    expect(value?.path, '/player/v1/6718335390845095173');
  });

  test('Facebook video uses official plugin rather than a raw direct URL', () {
    final value = alaniOfficialEmbed(
      Uri.parse('https://www.facebook.com/example/videos/123456789123456'));
    expect(value?.path, '/plugins/video.php');
    expect(value?.queryParameters['href'], contains('/videos/'));
  });

  test('short links, spoofed domains and HTTP never auto-embed', () {
    expect(alaniOfficialEmbed(Uri.parse('https://vt.tiktok.com/ZTEST/')), isNull);
    expect(alaniOfficialEmbed(Uri.parse('https://www.youtube.com.evil.test/watch?v=abcdefghijk')), isNull);
    expect(alaniOfficialEmbed(Uri.parse('http://www.youtube.com/watch?v=abcdefghijk')), isNull);
    expect(alaniOfficialEmbed(Uri.parse('https://www.facebook.com/example')), isNull);
  });
}
