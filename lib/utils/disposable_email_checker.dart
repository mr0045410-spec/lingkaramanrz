/// Utility untuk memvalidasi alamat email dan memblokir alamat email sementara (temp mail / disposable email).
class DisposableEmailChecker {
  DisposableEmailChecker._();

  /// Fast-path whitelist untuk penyedia email populer dan terpercaya.
  static const Set<String> _trustedDomains = {
    'gmail.com',
    'googlemail.com',
    'yahoo.com',
    'yahoo.co.id',
    'yahoo.co.uk',
    'yahoo.com.sg',
    'yahoo.co.jp',
    'ymail.com',
    'rocketmail.com',
    'outlook.com',
    'hotmail.com',
    'live.com',
    'msn.com',
    'icloud.com',
    'me.com',
    'mac.com',
    'proton.me',
    'protonmail.com',
    'pm.me',
    'zoho.com',
    'zohomail.com',
    'aol.com',
    'mail.com',
    'gmx.com',
    'gmx.net',
  };

  /// Daftar domain penyedia email sementara (disposable / temp mail) yang diblokir.
  static const Set<String> _disposableDomains = {
    // TempMail & variannya
    'tempmail.com',
    'temp-mail.org',
    'temp-mail.io',
    'tempmail.plus',
    'tempmail.ninja',
    'tempmail.net',
    'tempmailo.com',
    'tempmailgen.com',
    'tempmailaddress.com',
    'tempr.email',
    'tempinbox.com',
    'mytempemail.com',
    'mytemp.email',
    'mailtemp.net',

    // 10MinuteMail & variannya
    '10minutemail.com',
    '10minutemail.net',
    '10minutemail.org',
    '10minutemail.co.uk',
    '10minutemail.de',
    '10mail.org',
    '10mail.tk',
    '20minutemail.com',
    '30minutemail.com',
    'minutemailbox.com',

    // GuerrillaMail & variannya
    'guerrillamail.com',
    'guerrillamail.net',
    'guerrillamail.org',
    'guerrillamail.biz',
    'guerrillamail.de',
    'guerrillamail.info',
    'guerrillamailblock.com',
    'sharklasers.com',
    'grr.la',
    'spam4.me',
    'pokemail.net',

    // Mailinator & variannya
    'mailinator.com',
    'mailinator2.com',
    'mailinater.com',
    'suremail.info',
    'spamherelots.com',
    'binkmail.com',
    'bobmail.info',
    'chammy.info',
    'devnullmail.com',
    'letthemeatspam.com',
    'mailcatch.com',

    // YOPmail & variannya
    'yopmail.com',
    'yopmail.fr',
    'yopmail.net',
    'cool.fr.nf',
    'jetable.fr.nf',
    'courriel.fr.nf',
    'moncourrier.fr.nf',
    'monemail.fr.nf',
    'monmail.fr.nf',
    'hide.biz.st',
    'mymail.infos.st',

    // Trashmail & Burner
    'trashmail.com',
    'trashmail.net',
    'trashmail.me',
    'trashmail.ws',
    'trashmail.org',
    'trashymail.com',
    'burnermail.io',
    'throwawaymail.com',
    'disposablemail.com',
    'dispostable.com',
    'discard.email',
    'discardmail.com',
    'spambox.us',

    // Fake & Generator
    'fakemailgenerator.com',
    'fakemail.net',
    'fakeinbox.com',
    'emailfake.com',
    'emailfake.ml',
    'generator.email',
    'emailondeck.com',
    'crazymailing.com',
    'crazymail.com',

    // Nada & Airmail
    'getnada.com',
    'nada.ltd',
    'getairmail.com',
    'inboxbear.com',
    'dropmail.me',
    'maildrop.cc',
    'inboxkitten.com',
    'mohmal.com',
    'mohmal.im',
    'mohmal.in',
    'internxt.com',
    'zetmail.com',
    'bupmail.com',
    'mailnesia.com',
    'mailnesia.net',
    'mailnesia.org',
    'spambog.com',
    'spamgourmet.com',
    'harakirimail.com',
    'mytrashmail.com',
    'deadaddress.com',
    'mailexpire.com',
    'incognitomail.org',
    'incognitomail.com',
    'mailforspam.com',
    'safetymail.info',
    'filzmail.com',

    // Generator domains umum
    'armyspy.com',
    'cuvox.de',
    'dayrep.com',
    'einrot.com',
    'fleckens.hu',
    'gustr.com',
    'jourrapide.com',
    'rhyta.com',
    'superrito.com',
    'teleworm.us',
    'wegwerfmail.de',
    'wegwerfmail.net',
    'wegwerfemail.de',
    'hidemail.de',
    'kasmail.com',
    'spamex.com',
    'tmail.ws',
    'tmail.link',
    'tmailor.com',
    'chacuo.net',
    '0-mail.com',
    '0clickemail.com',
    '0wnd.net',
    '0wnd.org',
    '2prong.com',
    '33mail.com',
  };

  /// Keyword mencurigakan yang sering digunakan domain email sekali pakai baru.
  static const List<String> _suspiciousKeywords = [
    'tempmail',
    'temp-mail',
    '10minute',
    'guerrillamail',
    'mailinator',
    'throwaway',
    'trashmail',
    'disposab',
    'fakemail',
    'burnermail',
    'yopmail',
    'getnada',
    'mohmal',
    'sharklaser',
    'maildrop',
    'wegwerf',
    'jetable',
    'emailfake',
    'dropmail',
    'spambox',
    'inboxkitten',
  ];

  /// Menguji apakah [email] berasal dari domain disposable/temp mail.
  static bool isDisposable(String email) {
    final trimmed = email.trim().toLowerCase();
    if (!trimmed.contains('@')) return false;

    final parts = trimmed.split('@');
    if (parts.length != 2) return false;

    final domain = parts[1].trim();
    if (domain.isEmpty) return false;

    // 1. Fast path: jika domain resmi terpercaya, langsung lolos
    if (_trustedDomains.contains(domain)) {
      return false;
    }

    // Domain institusi/kampus Indonesia (.ac.id, .go.id, .sch.id)
    if (domain.endsWith('.ac.id') || domain.endsWith('.go.id') || domain.endsWith('.sch.id')) {
      return false;
    }

    // 2. Blacklist path: cek apakah ada di daftar blacklist
    if (_disposableDomains.contains(domain)) {
      return true;
    }

    // 3. Keyword heuristic path: cek apakah nama domain mengandung kata kunci mencurigakan
    for (final kw in _suspiciousKeywords) {
      if (domain.contains(kw)) {
        return true;
      }
    }

    return false;
  }

  /// Memvalidasi format email sekaligus memastikan bukan email sementara.
  /// Mengembalikan pesan error (String) jika tidak valid, atau `null` jika valid.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Alamat email wajib diisi';
    }

    final trimmed = value.trim();

    // Validasi format email dasar
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,6}$');
    if (!emailRegex.hasMatch(trimmed)) {
      return 'Format alamat email tidak valid (contoh: nama@gmail.com)';
    }

    // Validasi anti-temp mail
    if (isDisposable(trimmed)) {
      return 'Email sementara (temp mail) dilarang. Harap gunakan email asli seperti Gmail, Yahoo, atau Outlook.';
    }

    return null;
  }
}
