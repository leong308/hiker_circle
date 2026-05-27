import '../Model/otp_challenge.dart';
import 'green_api_client.dart';
import 'phone_number_formatter.dart';

class GreenApiOtpRepository {
  GreenApiOtpRepository({required GreenApiClient greenApiClient})
    : _greenApiClient = greenApiClient;

  final GreenApiClient _greenApiClient;

  Future<OtpChallenge> sendLoginCode(String rawPhoneNumber) async {
    final phoneNumber = PhoneNumberFormatter.normalize(rawPhoneNumber);
    final challenge = OtpChallenge.generate(phoneNumber: phoneNumber);

    await _greenApiClient.sendMessage(
      chatId: PhoneNumberFormatter.toWhatsAppChatId(phoneNumber),
      message:
          'Your HikerCircle verification code is ${challenge.code}. '
          'It expires in ${challenge.ttl.inMinutes} minutes.',
    );

    return challenge.hideCode();
  }
}
