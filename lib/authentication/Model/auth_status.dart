// AuthMode and AuthStatus describe the authentication form and its current operation state.
/// Defines the auth mode choices.
enum AuthMode { signUp, login }

/// Defines the auth status choices.
enum AuthStatus {
  enteringPhone,
  sendingCode,
  enteringCode,
  verifyingCode,
  loggingIn,
  signedIn,
}
