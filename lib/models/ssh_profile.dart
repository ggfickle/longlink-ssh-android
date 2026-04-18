enum SshAuthType {
  password('password'),
  privateKey('privateKey');

  const SshAuthType(this.value);

  final String value;

  static SshAuthType fromValue(String value) {
    return SshAuthType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => SshAuthType.password,
    );
  }
}

class SshProfile {
  const SshProfile({
    required this.id,
    required this.displayName,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    required this.connectionTimeoutSeconds,
    required this.keepAliveIntervalSeconds,
    this.reusableKeyId,
  });

  final String id;
  final String displayName;
  final String host;
  final int port;
  final String username;
  final SshAuthType authType;
  final int connectionTimeoutSeconds;
  final int keepAliveIntervalSeconds;
  final String? reusableKeyId;

  bool get usesReusableKey =>
      authType == SshAuthType.privateKey &&
      (reusableKeyId?.trim().isNotEmpty ?? false);

  SshProfile copyWith({
    String? id,
    String? displayName,
    String? host,
    int? port,
    String? username,
    SshAuthType? authType,
    int? connectionTimeoutSeconds,
    int? keepAliveIntervalSeconds,
    String? reusableKeyId,
    bool clearReusableKeyId = false,
  }) {
    return SshProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      connectionTimeoutSeconds:
          connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      keepAliveIntervalSeconds:
          keepAliveIntervalSeconds ?? this.keepAliveIntervalSeconds,
      reusableKeyId: clearReusableKeyId
          ? null
          : reusableKeyId ?? this.reusableKeyId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'host': host,
      'port': port,
      'username': username,
      'authType': authType.value,
      'connectionTimeoutSeconds': connectionTimeoutSeconds,
      'keepAliveIntervalSeconds': keepAliveIntervalSeconds,
      'reusableKeyId': reusableKeyId,
    };
  }

  factory SshProfile.fromJson(Map<String, dynamic> json) {
    return SshProfile(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 22,
      username: json['username'] as String? ?? '',
      authType: SshAuthType.fromValue(json['authType'] as String? ?? ''),
      connectionTimeoutSeconds: json['connectionTimeoutSeconds'] as int? ?? 30,
      keepAliveIntervalSeconds: json['keepAliveIntervalSeconds'] as int? ?? 15,
      reusableKeyId: _blankToNull(json['reusableKeyId'] as String?),
    );
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class SshProfileSecrets {
  const SshProfileSecrets({this.password, this.privateKey, this.passphrase});

  final String? password;
  final String? privateKey;
  final String? passphrase;

  bool get hasPassword => (password ?? '').trim().isNotEmpty;
  bool get hasPrivateKey => (privateKey ?? '').trim().isNotEmpty;
  bool get hasPassphrase => (passphrase ?? '').trim().isNotEmpty;
}
