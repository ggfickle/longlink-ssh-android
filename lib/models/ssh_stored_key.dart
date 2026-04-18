class SshStoredKey {
  const SshStoredKey({
    required this.id,
    required this.name,
    required this.publicKey,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    required this.hasPassphrase,
  });

  final String id;
  final String name;
  final String publicKey;
  final int createdAtMillis;
  final int updatedAtMillis;
  final bool hasPassphrase;

  String get algorithm {
    final parts = publicKey.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'ssh-key' : parts.first;
  }

  String get publicKeySummary {
    final trimmed = publicKey.trim();
    if (trimmed.isEmpty) {
      return 'Public key unavailable';
    }
    if (trimmed.length <= 80) {
      return trimmed;
    }
    return '${trimmed.substring(0, 77)}...';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'publicKey': publicKey,
      'createdAtMillis': createdAtMillis,
      'updatedAtMillis': updatedAtMillis,
      'hasPassphrase': hasPassphrase,
    };
  }

  factory SshStoredKey.fromJson(Map<String, dynamic> json) {
    return SshStoredKey(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'SSH key',
      publicKey: json['publicKey'] as String? ?? '',
      createdAtMillis: json['createdAtMillis'] as int? ?? 0,
      updatedAtMillis:
          json['updatedAtMillis'] as int? ??
          json['createdAtMillis'] as int? ??
          0,
      hasPassphrase: json['hasPassphrase'] as bool? ?? false,
    );
  }
}

class SshStoredKeySecrets {
  const SshStoredKeySecrets({this.privateKey, this.passphrase});

  final String? privateKey;
  final String? passphrase;

  bool get hasPrivateKey => (privateKey ?? '').trim().isNotEmpty;
  bool get hasPassphrase => (passphrase ?? '').trim().isNotEmpty;
}
