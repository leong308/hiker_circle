# HikerCircle guide assistant

The assistant uses reviewed articles in `functions/hiker_circle_assistant.js`. It retrieves matching guides and returns their content and source titles through `askHikerCircleAssistant`. It does not generate answers or contact a model provider. Existing emergency guidance, authenticated access, rate limits, live trail lookup and approved navigation buttons remain available. Chat history continues to sync through the existing account storage.

Related client code: `lib/assistant/Data/hiker_circle_assistant_repository.dart`, `lib/assistant/View/hiker_circle_assistant_page.dart` and `lib/assistant/Data/hiker_circle_assistant_history_store.dart`. No provider API key is required.

Run `node --test functions/test/hiker_circle_assistant.test.js` and `flutter test test/assistant/`. Deploy `askHikerCircleAssistant` after changing server-side guides. Guide retrieval is deterministic and cannot answer arbitrary questions outside the reviewed material.
