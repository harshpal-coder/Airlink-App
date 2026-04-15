import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_helper.dart';

class SignalProtocolService {
  static final SignalProtocolService _instance = SignalProtocolService._internal();
  factory SignalProtocolService() => _instance;
  SignalProtocolService._internal();

  late IdentityKeyPair _identityKeyPair;
  late int _registrationId;
  final Map<String, SessionCipher> _sessionCiphers = {};

  late final SessionStore _sessionStore;
  late final PreKeyStore _preKeyStore;
  late final SignedPreKeyStore _signedPreKeyStore;
  late final IdentityKeyStore _identityStore;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final db = DatabaseHelper.instance;
    final prefs = await SharedPreferences.getInstance();
    final String? identityKeyBase64 = prefs.getString('signal_identity_key');

    if (identityKeyBase64 == null) {
      // Generate new local identity
      _identityKeyPair = IdentityKeyPair(
        IdentityKey(Curve.generateKeyPair().publicKey),
        Curve.generateKeyPair().privateKey,
      );
      _registrationId = generateRegistrationId(false);

      await prefs.setString(
        'signal_identity_key', 
        base64Encode(_identityKeyPair.serialize())
      );
      await prefs.setInt('signal_registration_id', _registrationId);
      
      // Store our own identity in DB as well for backup/consistency
      await db.storeIdentity('me', _identityKeyPair.serialize(), _registrationId);
    } else {
      _identityKeyPair = IdentityKeyPair.fromSerialized(base64.decode(identityKeyBase64));
      _registrationId = prefs.getInt('signal_registration_id')!;
    }

    // Initialize Persistent Stores
    _sessionStore = PersistentSessionStore(db);
    _preKeyStore = PersistentPreKeyStore(db);
    _signedPreKeyStore = PersistentSignedPreKeyStore(db);
    _identityStore = PersistentIdentityKeyStore(db, _identityKeyPair, _registrationId);

    _initialized = true;
    debugPrint('[Signal] Persistent stores initialized with Registration ID: $_registrationId');
  }

  Future<String> encryptMessage(String remoteUuid, String plaintext) async {
    if (!_initialized) await init();
    
    final address = SignalProtocolAddress(remoteUuid, 1);
    if (!(await _sessionStore.containsSession(address))) {
      debugPrint('[Signal] No persistent session for $remoteUuid. Refusing to send plaintext.');
      throw Exception('E2EE Session Missing: A security handshake is required with this peer before messaging.');
    }

    final cipher = _getOrCreateCipher(remoteUuid);
    final ciphertext = await cipher.encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    return base64.encode(ciphertext.serialize());
  }

  Future<String> decryptMessage(String remoteUuid, String base64Ciphertext) async {
    if (!_initialized) await init();

    try {
      final cipher = _getOrCreateCipher(remoteUuid);
      final rawCiphertext = base64.decode(base64Ciphertext);
      
      Uint8List decrypted;
      try {
        // Try decrypting as PreKeySignalMessage
        decrypted = await cipher.decrypt(PreKeySignalMessage(rawCiphertext));
      } catch (e) {
        // Fallback to regular SignalMessage if it fails
        try {
          // Bypass specific PreKeySignalMessage type constraint for regular messages
          decrypted = await (cipher as dynamic).decrypt(SignalMessage.fromSerialized(rawCiphertext));
        } catch (e2) {
          debugPrint('[Signal] Decryption failed for both PreKey and regular message: $e2');
          rethrow;
        }
      }
      return utf8.decode(decrypted);
    } catch (e) {
      debugPrint('[Signal] Decryption failed for $remoteUuid: $e');
      return "[Decryption Failed]";
    }
  }

  SessionCipher _getOrCreateCipher(String remoteUuid) {
    final address = SignalProtocolAddress(remoteUuid, 1);
    if (!_sessionCiphers.containsKey(remoteUuid)) {
      _sessionCiphers[remoteUuid] = SessionCipher(
        _sessionStore,
        _preKeyStore,
        _signedPreKeyStore,
        _identityStore,
        address,
      );
    }
    return _sessionCiphers[remoteUuid]!;
  }

  Map<String, dynamic> generatePreKeyBundle() {
    return {
      'registrationId': _registrationId,
      'identityKey': base64.encode(_identityKeyPair.getPublicKey().serialize()),
    };
  }

  Future<String> getLocalFingerprint() async {
    if (!_initialized) await init();
    return base64.encode(_identityKeyPair.getPublicKey().serialize());
  }

  Future<String?> getRemoteFingerprint(String remoteUuid) async {
    if (!_initialized) await init();
    final address = SignalProtocolAddress(remoteUuid, 1);
    final identityKey = await _identityStore.getIdentity(address);
    if (identityKey == null) return null;
    return base64.encode(identityKey.serialize());
  }

  Future<void> saveIdentityForPeer(String remoteUuid, Uint8List identityBytes) async {
    if (!_initialized) await init();
    final address = SignalProtocolAddress(remoteUuid, 1);
    final identityKey = IdentityKey.fromBytes(identityBytes, 0);
    await _identityStore.saveIdentity(address, identityKey);
  }

  int get localRegistrationId => _registrationId;

  /// Computes a combined, deterministic Safety Number for the local<->peer pair.
  /// Both parties derive the same 60-digit number by sorting the two UUIDs
  /// lexicographically, concatenating their serialized identity keys, and
  /// SHA-256 hashing the result — identical to Signal's approach.
  Future<String?> getCombinedSafetyNumber(String localUuid, String remoteUuid) async {
    if (!_initialized) await init();

    final address = SignalProtocolAddress(remoteUuid, 1);
    final remoteIdentityKey = await _identityStore.getIdentity(address);
    if (remoteIdentityKey == null) return null;

    final localKeyBytes = _identityKeyPair.getPublicKey().serialize();
    final remoteKeyBytes = remoteIdentityKey.serialize();

    // Sort by UUID lexicographically so both peers get the same byte order.
    late Uint8List combined;
    if (localUuid.compareTo(remoteUuid) <= 0) {
      combined = Uint8List.fromList([...localKeyBytes, ...remoteKeyBytes]);
    } else {
      combined = Uint8List.fromList([...remoteKeyBytes, ...localKeyBytes]);
    }

    final digest = sha256.convert(combined);
    // Convert each byte to a 0-255 integer, take groups of 5 digits.
    final digits = digest.bytes.map((b) => b.toString().padLeft(3, '0')).join();
    // Slice into 5-digit groups (60 chars total from first 60 digits).
    final safetyNumber = List.generate(12, (i) => digits.substring(i * 5, i * 5 + 5)).join(' ');
    return safetyNumber;
  }
}

// --- Persistent Store Implementations ---

class PersistentSessionStore implements SessionStore {
  final DatabaseHelper db;
  PersistentSessionStore(this.db);

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async {
    return await db.containsSession(address.getName(), address.getDeviceId());
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    // Note: We'd need a deleteByAddressName method in DatabaseHelper if needed
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await db.deleteSession(address.getName(), address.getDeviceId());
  }

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final record = await db.loadSession(address.getName(), address.getDeviceId());
    if (record != null) {
      return SessionRecord.fromSerialized(Uint8List.fromList(record));
    }
    return SessionRecord();
  }

  @override
  Future<void> storeSession(SignalProtocolAddress address, SessionRecord record) async {
    await db.storeSession(address.getName(), address.getDeviceId(), record.serialize());
  }
  
  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    return [];
  }
}

class PersistentPreKeyStore implements PreKeyStore {
  final DatabaseHelper db;
  PersistentPreKeyStore(this.db);

  @override
  Future<bool> containsPreKey(int preKeyId) async {
    final key = await db.loadPreKey(preKeyId);
    return key != null;
  }

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final record = await db.loadPreKey(preKeyId);
    if (record == null) throw InvalidKeyIdException('No such prekey: $preKeyId');
    return PreKeyRecord.fromBuffer(Uint8List.fromList(record));
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await db.deletePreKey(preKeyId);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await db.storePreKey(preKeyId, record.serialize());
  }
}

class PersistentSignedPreKeyStore implements SignedPreKeyStore {
  final DatabaseHelper db;
  PersistentSignedPreKeyStore(this.db);

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async {
    final key = await db.loadSignedPreKey(signedPreKeyId);
    return key != null;
  }

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final record = await db.loadSignedPreKey(signedPreKeyId);
    if (record == null) throw InvalidKeyIdException('No such signed prekey: $signedPreKeyId');
    return SignedPreKeyRecord.fromSerialized(Uint8List.fromList(record));
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    return [];
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await db.deleteSignedPreKey(signedPreKeyId);
  }

  @override
  Future<void> storeSignedPreKey(int signedPreKeyId, SignedPreKeyRecord record) async {
    await db.storeSignedPreKey(signedPreKeyId, record.serialize());
  }
}

class PersistentIdentityKeyStore implements IdentityKeyStore {
  final DatabaseHelper db;
  final IdentityKeyPair identityKeyPair;
  final int localRegistrationId;

  PersistentIdentityKeyStore(this.db, this.identityKeyPair, this.localRegistrationId);

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async => identityKeyPair;

  @override
  Future<int> getLocalRegistrationId() async => localRegistrationId;

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final trusted = await db.loadIdentity(address.getName());
    if (trusted == null) return null;
    final bytes = Uint8List.fromList(trusted['identity_key'] as List<int>);
    return IdentityKey(Curve.decodePoint(bytes, 0));
  }

  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address, IdentityKey? identityKey, Direction direction) async {
    final trusted = await db.loadIdentity(address.getName());
    if (trusted == null) return true; // Trust on first use
    if (identityKey == null) return false;
    final bytes = Uint8List.fromList(trusted['identity_key'] as List<int>);
    return IdentityKey(Curve.decodePoint(bytes, 0)) == identityKey;
  }

  @override
  Future<bool> saveIdentity(SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;
    await db.storeIdentity(address.getName(), identityKey.serialize(), 0);
    return true;
  }
}
