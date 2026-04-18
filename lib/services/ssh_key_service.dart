import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;

class GeneratedSshKeyPair {
  const GeneratedSshKeyPair({
    required this.privateKeyPem,
    required this.publicKeyAuthorized,
    required this.comment,
  });

  final String privateKeyPem;
  final String publicKeyAuthorized;
  final String comment;
}

class SshKeyService {
  const SshKeyService();

  GeneratedSshKeyPair generateEd25519({required String comment}) {
    final normalizedComment = comment.trim().isEmpty
        ? 'longlink@android'
        : comment.trim();
    final signingKey = ed25519.SigningKey.generate();
    final keyPair = OpenSSHEd25519KeyPair(
      signingKey.verifyKey.asTypedList,
      signingKey.asTypedList,
      normalizedComment,
    );

    return GeneratedSshKeyPair(
      privateKeyPem: keyPair.toPem(),
      publicKeyAuthorized: formatAuthorizedKey(
        keyPair.toPublicKey().encode(),
        comment: normalizedComment,
      ),
      comment: normalizedComment,
    );
  }

  String? deriveAuthorizedPublicKey(
    String privateKeyPem, {
    String? passphrase,
    String? fallbackComment,
  }) {
    final normalizedPem = privateKeyPem.trim();
    if (normalizedPem.isEmpty) {
      return null;
    }

    final keyPairs = SSHKeyPair.fromPem(
      normalizedPem,
      _blankToNull(passphrase),
    );
    if (keyPairs.isEmpty) {
      return null;
    }

    final keyPair = keyPairs.first;
    return formatAuthorizedKey(
      keyPair.toPublicKey().encode(),
      comment: _commentFor(keyPair) ?? _blankToNull(fallbackComment),
    );
  }

  String formatAuthorizedKey(Uint8List encodedPublicKey, {String? comment}) {
    final type = _extractSshType(encodedPublicKey);
    final suffix = _blankToNull(comment);
    final encoded = base64.encode(encodedPublicKey);
    return suffix == null ? '$type $encoded' : '$type $encoded $suffix';
  }

  String? _commentFor(SSHKeyPair keyPair) {
    switch (keyPair) {
      case OpenSSHRsaKeyPair():
        return _blankToNull(keyPair.comment);
      case OpenSSHEd25519KeyPair():
        return _blankToNull(keyPair.comment);
      case OpenSSHEcdsaKeyPair():
        return _blankToNull(keyPair.comment);
      default:
        return null;
    }
  }

  String _extractSshType(Uint8List encodedPublicKey) {
    if (encodedPublicKey.length < 4) {
      throw const FormatException('Invalid SSH public key payload.');
    }

    final data = ByteData.sublistView(encodedPublicKey);
    final typeLength = data.getUint32(0);
    if (encodedPublicKey.length < 4 + typeLength) {
      throw const FormatException('Invalid SSH public key type length.');
    }

    return utf8.decode(encodedPublicKey.sublist(4, 4 + typeLength));
  }

  String? _blankToNull(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
