import 'package:flutter_test/flutter_test.dart';
import 'package:abess_vpn/security/privacy.dart';
void main(){
  test('diagnostics mask reusable credentials and infrastructure IPs',(){
    final report=redactDiagnostics('ABESS-ABCDEFG1234 vless://secret@host:443 123e4567-e89b-12d3-a456-426614174000 192.0.2.1 2001:db8::1 password=example');
    for(final value in ['ABESS-ABCDEFG1234','secret@host','123e4567','192.0.2.1','2001:db8::1','password=example']){expect(report.contains(value),isFalse);}
  });
  test('JSON SSH diagnostics never contain reusable passwords', () {
    final report = redactDiagnostics('{"sshPassword":"ssh-secret-one","password":"ssh-secret-two"} ssh://user:pass@example.test');
    expect(report.contains('ssh-secret-one'), isFalse);
    expect(report.contains('ssh-secret-two'), isFalse);
    expect(report.contains('user:pass'), isFalse);
  });
  test('update origin cannot be supplied by an imported VPN profile',(){
    expect(isTrustedUpdateUrl('https://evil.example/app.apk','https://control.example'),isFalse);
    expect(isTrustedUpdateUrl('http://control.example/app.apk','https://control.example'),isFalse);
    expect(isTrustedUpdateUrl('https://control.example/app.apk','https://control.example'),isTrue);
    expect(isTrustedUpdateUrl('https://github.com/abesskamer237/AbessVpn-Cyber/releases/latest',''),isTrue);
    expect(isTrustedUpdateUrl('https://github.com/another/project/releases/latest',''),isFalse);
  });
}
