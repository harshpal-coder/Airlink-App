import 'dart:convert';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignalProtocolService {
  static final SignalProtocolService _instance = SignalProtocolService._internal();
  factory SignalProtocolService() => _instance;
  SignalProtocolService._internal();

  late IdentityKeyPair _identityKeyPair;
  late int _registrationId;
  final Map<String, SessionCipher> _sessionCiphers = {};

  // Simple in-memory stores for prototype. 
  // In a real app, these should persist to SQLite.
  final _sessionStore = InMemorySessionStore();
  final _preKeyStore = InMemoryPreKeyStore();
  final _signedPreKeyStore = InMemorySignedPreKeyStore();
  final _identityStore = InMemoryIdentityKeyStore(
    IdentityKeyPair(
        IdentityKey(Curve.generateKeyPair().publicKey), 
        Curve.generateKeyPair().privateKey), 
    1234
  );

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final String? identityKeyBase64 = prefs.getString('signal_identity_key');

    if (identityKeyBase64 == null) {
      // Generate new identity
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
    } else {
      _identityKeyPair = IdentityKeyPair.fromSerialized(base64.decode(identityKeyBase64));
      _registrationId = prefs.getInt('signal_registration_id')!;
    }

    // Re-initialize identity store with persisted values
    _initialized = true;
    debugPrint('[Signal] Initialized with Registration ID: $_registrationId');
  }

  Future<String> encryptMessage(String remoteUuid, String plaintext) async {
    if (!_initialized) await init();
    
    // Check if session exists
    if (!(await _sessionStore.containsSession(SignalProtocolAddress(remoteUuid, 1)))) {
      // In a real mesh, we'd request PreKeys here. 
      // For the prototype, we assume a session is established or we use a fallback.
      debugPrint('[Signal] No session for $remoteUuid. Returning plaintext (unsecured).');
      return plaintext; 
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
        // Try as PreKeySignalMessage (often used for initial messages)
        decrypted = await cipher.decrypt(PreKeySignalMessage(rawCiphertext));
      } catch (e) {
        debugPrint('[Signal] Decryption failed or not a PreKeySignalMessage: $e');
        // For prototype, we treat failure as decryption failure
        rethrow;
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

  // --- Key Exchange Logic ---
  Map<String, dynamic> generatePreKeyBundle() {
    // Simplified for prototype: bundle contains public keys for exchange
    return {
      'registrationId': _registrationId,
      'identityKey': base64.encode(_identityKeyPair.getPublicKey().serialize()),
      // PreKeys and SignedPreKeys would go here in a full implementation
    };
  }
}
