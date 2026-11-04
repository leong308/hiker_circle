# Persistent user constraint

Do not add or re-enable Firebase App Check or Play Integrity in HikerCircle.
This applies to every app target, native startup, build configuration, backend
callable, deployment setting, and test fixture. Do not register debug tokens or
add attestation-token refresh/retry flows.

Keep the existing password, WhatsApp OTP, MFA, Firebase Authentication,
server-owned mobile session, account-role checks, and database rules. Firebase
SDK interoperability interfaces that are required transitively are not providers
and must not be stripped out of the SDK dependency graph.
