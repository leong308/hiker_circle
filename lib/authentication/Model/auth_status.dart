// AuthMode and AuthStatus describe the authentication form and its current operation state.
enum AuthMode { signUp, login }

enum AuthStatus {
  enteringPhone,
  sendingCode,
  enteringCode,
  verifyingCode,
  loggingIn,
  signedIn,
}
