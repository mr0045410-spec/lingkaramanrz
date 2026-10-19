import 'package:flutter_test/flutter_test.dart';
import 'package:lingkar_aman/utils/disposable_email_checker.dart';

void main() {
  group('DisposableEmailChecker Tests', () {
    test('Trusted domains are accepted', () {
      final trustedEmails = [
        'budi@gmail.com',
        'siti.rahma@yahoo.com',
        'andi@outlook.com',
        'joko@hotmail.com',
        'user@icloud.com',
        'privacy@proton.me',
        'work@zoho.com',
        'dosen@ui.ac.id',
        'staff@kemkes.go.id',
        'siswa@sman1.sch.id',
      ];

      for (final email in trustedEmails) {
        expect(
          DisposableEmailChecker.isDisposable(email),
          isFalse,
          reason: 'Expected $email to NOT be disposable',
        );
        expect(
          DisposableEmailChecker.validateEmail(email),
          isNull,
          reason: 'Expected $email validation to succeed',
        );
      }
    });

    test('Known disposable/temp mail domains are blocked', () {
      final tempEmails = [
        'attacker@tempmail.com',
        'fake@10minutemail.com',
        'spammer@guerrillamail.com',
        'test@mailinator.com',
        'anon@yopmail.com',
        'junk@trashmail.com',
        'bot@burnermail.io',
        'throw@throwawaymail.com',
        'ninja@tempmail.ninja',
        'shark@sharklasers.com',
        'nada@getnada.com',
        'drop@maildrop.cc',
        'mohmal@mohmal.com',
        'inbox@inboxkitten.com',
        'custom@tempmail-generator.org', // matches tempmail keyword
        'random@mytrashmail.net',       // matches trashmail keyword
      ];

      for (final email in tempEmails) {
        expect(
          DisposableEmailChecker.isDisposable(email),
          isTrue,
          reason: 'Expected $email to be detected as disposable',
        );
        final error = DisposableEmailChecker.validateEmail(email);
        expect(
          error,
          contains('Email sementara (temp mail) dilarang'),
          reason: 'Expected rejection message for $email',
        );
      }
    });

    test('Invalid email formats are rejected', () {
      expect(DisposableEmailChecker.validateEmail(''), 'Alamat email wajib diisi');
      expect(DisposableEmailChecker.validateEmail(null), 'Alamat email wajib diisi');
      expect(DisposableEmailChecker.validateEmail('budi'), contains('tidak valid'));
      expect(DisposableEmailChecker.validateEmail('budi@'), contains('tidak valid'));
      expect(DisposableEmailChecker.validateEmail('budi@gmail'), contains('tidak valid'));
    });
  });
}
