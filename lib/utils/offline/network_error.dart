import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Thrown when there is no connection to use (or the app is working offline).
class OfflineException implements Exception {
  const OfflineException([this.message = 'You are offline.']);
  final String message;
  @override
  String toString() => message;
}

/// Whether [error] means the server could not be reached, as opposed to the
/// server answering with a refusal.
bool isNetworkError(Object error) {
  // (A request cut short because the page that made it was closed is not the
  // connection failing.)
  if (error is http.ClientException) {
    return !error.message.toLowerCase().contains('closed');
  }
  return error is OfflineException ||
      error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      (error is FirebaseAuthException &&
          (error.code == 'network-request-failed' ||
              error.code == 'internal-error'));
}
