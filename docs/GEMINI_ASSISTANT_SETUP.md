# HikerCircle Assistant — Gemini Free-Tier Setup

## What is implemented

The first release is available from:

`Profile → App Settings → HikerCircle Assistant → Ask HikerCircle`

The mobile app calls the authenticated Firebase callable function
`askHikerCircleAssistant`. The Gemini API key never enters the Flutter app.
The function retrieves up to three reviewed HikerCircle help articles and asks
Gemini only to compose a short answer from those articles.

The implementation also:

- rejects unauthenticated requests;
- does not save chat history;
- rejects common phone numbers, email addresses, verification codes, and exact
  latitude/longitude pairs before calling Gemini;
- answers obvious emergency prompts locally without sending them to Gemini;
- limits each account to 6 requests per minute and 40 requests per UTC day;
- uses `gemini-3.5-flash-lite`, with `gemini-3.1-flash-lite` as a second
  free-tier attempt when the primary model is temporarily overloaded;
- returns the matching reviewed HikerCircle guide directly when both free
  models are busy or the unpaid quota is unavailable; and
- shows an inline animated AI-thinking bubble, with a 30-second client
  watchdog.

## Keep Gemini usage strictly on the unpaid quota

The existing HikerCircle Firebase project uses Blaze for Cloud Functions. To
prevent Gemini usage from silently becoming billable, create the Gemini API key
in a separate Google AI Studio project that has **no billing account linked**.
The key can still be stored and used by the HikerCircle Firebase function.

1. Open [Google AI Studio API Keys](https://aistudio.google.com/app/apikey).
2. Create a new Google Cloud project, for example
   `hiker-circle-assistant-free`.
3. On the AI Studio Projects or Usage page, confirm that this new project is on
   the **Free** tier.
4. Do **not** choose **Set up billing**, do not link a billing account, and do
   not upgrade this project to Tier 1.
5. Create an API key in that free-tier project.
6. In Google Cloud Console, restrict that key to the **Generative Language
   API** where the credential controls allow it.

Gemini rate limits apply per Google Cloud project. When the free limit is
reached, Gemini returns HTTP 429 and HikerCircle shows a quota-exhausted message.
It does not switch to another key or model.

> Free-tier prompts and answers may be used by Google to improve its products
> and may be reviewed by humans. Keep this assistant limited to general app
> help. Never send passwords, OTPs, authenticator codes, passkey data, precise
> locations, medical details, or user profile data.

## Store the key in Firebase Secret Manager

From the HikerCircle repository root, sign in to the Firebase CLI and target the
existing HikerCircle Firebase project explicitly. Then run:

```powershell
firebase functions:secrets:set GEMINI_API_KEY --project hiker-circle
```

Paste the Gemini API key only at the CLI prompt. Do not place it in Dart code,
JavaScript source, `.env`, Git, screenshots, or documentation.

Confirm CLI access if needed:

```powershell
firebase projects:list
```

## Deploy only the assistant function

Run the automated function tests first:

```powershell
Set-Location functions
npm test
Set-Location ..
```

Then deploy only this callable function:

```powershell
firebase deploy --only functions:askHikerCircleAssistant --project hiker-circle
```

The function is configured in `us-central1`, requires Firebase Authentication,
has a 30-second timeout, and can scale to at most four instances.

## Verify the setup

1. Sign in to HikerCircle.
2. Open `Profile → App Settings → HikerCircle Assistant`.
3. Ask: `Where can I manage my passkey?`
4. Confirm the answer cites `Login and account security`.
5. In Google AI Studio, open **Usage & Rate Limits** for the separate assistant
   project and confirm that it still reports **Free** tier.
6. Search Firebase Functions logs for `askHikerCircleAssistant` if the app says
   the assistant is not configured.

Expected failures:

| App message | Meaning | Action |
| --- | --- | --- |
| Assistant is not configured | Secret is absent or empty | Set `GEMINI_API_KEY`, then redeploy |
| API key is missing or not permitted | Wrong key or API restriction | Check the key and Generative Language API |
| Answer says it came directly from a reviewed guide | Free Gemini capacity or quota was unavailable | The answer remains usable; retry later for AI-composed wording |
| Asked several questions quickly | HikerCircle per-user minute limit | Wait one minute |
| Free assistant allowance is used for today | HikerCircle per-user daily limit | Wait until the next UTC day |

## Cost boundary

This setup keeps **Gemini model usage** on the unpaid Gemini Developer API tier.
It does not make the rest of Firebase free. The callable function, Secret
Manager, Firestore `assistantUsage` rate-limit documents, networking, and the
existing HikerCircle backend remain subject to the Firebase/Google Cloud billing
and free allowances already attached to the main HikerCircle project.

## Backend data created

The callable creates one backend-only document per authenticated user:

`assistantUsage/{firebaseUid}`

Fields:

| Field | Type | Purpose |
| --- | --- | --- |
| `minuteBucket` | integer | Current UTC epoch-minute bucket |
| `minuteCount` | integer | Requests consumed in that minute |
| `dayBucket` | string | UTC day in `YYYY-MM-DD` format |
| `dayCount` | integer | Requests consumed that day |
| `updatedAt` | string | ISO timestamp of the last request |

The app never reads or writes this collection directly. Firebase Admin access
inside the callable function maintains it, so no client Firestore rule is
required.

## Updating the assistant knowledge

Reviewed articles are in:

`functions/hiker_circle_assistant.js`

Update an article when a related HikerCircle workflow changes, run
`node --test test/hiker_circle_assistant.test.js` inside `functions`, and deploy
the callable again. Do not add account records, private messages, exact
locations, SOS payloads, or any other personal data to the prompt context.
