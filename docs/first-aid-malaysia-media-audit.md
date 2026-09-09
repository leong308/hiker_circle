# Malaysia first-aid video replacement audit

Reviewed 9 September 2026. Following approval to use intact KKM originals, two verified files have been uploaded to Firebase and read back with matching SHA-256 hashes. The updated app manifest selects these files; an updated app build is required. Android/iOS device playback has not been verified in this change.

## Implemented coverage

- Heat exhaustion: KKM InfoSihat `TANDA2 STROK HABA 2.0.mp4`, 37.55 seconds, 4,348,400 bytes. Source: https://infosihat.moh.gov.my/cuaca-panas.html. Storage: `first_aid/videos/kkm_heat_awareness_v2.mp4`. SHA-256: `b9ecb95a753160c80878fc3c937fa1fea3507e712e599d82ba3e84daf324903d`.
- Severe weather: KKM **Panduan Semasa Banjir**, 24.57 seconds, 12,921,264 bytes. Source: https://infosihat.moh.gov.my/penerbitan-multimedia/video/item/panduan-semasa-banjir.html. Storage: `first_aid/videos/kkm_flood_health_v2.mp4`. SHA-256: `472b6f90c83954e4ba4b1947bc03758b1c46efe63461f8efcfa90be7dcafa5c2`.

Both are Bahasa Melayu awareness references, not treatment demonstrations. Visible scope notes distinguish heat warning signs from cooling instruction and flood hygiene from lightning/rescue instruction. Full originals, credits and intros are preserved byte-for-byte. KKM ownership credits were visually inspected. No re-encoding, cuts or dubbing were performed.

The other five categories retain written guidance but explicitly have no verified matching KKM video. All seven old US video references were removed from the updated manifest; existing storage objects were not deleted to avoid breaking older app builds. Version-2 cache names cannot select version-1 clips; downloaded files are checked against the source SHA-256. The old US importer now refuses to run.

Publish/verify with `node scripts/import_kkm_first_aid_videos.cjs --apply` or `--verify`. The script refuses non-KKM sources and uploads new immutable objects, verifies length/hash and reads Firebase bytes back. Permission is documented below, not represented as public-domain status. Existing written guidance outside the heat category retains its actual source attribution; this change does not claim that all written content was authored or clinically approved by KKM.

## Current problem

The bundled `assets/guides/first_aid_guide.json` references seven US-government/DVIDS clips. Several are news, military training or prevention pieces, rather than direct demonstrations of the category's first-aid actions. A public-domain label does not establish clinical suitability for Malaysian hikers. Reusing these as generic tutorials was not an adequate content-selection standard.

## Verified reuse evidence

[KKM InfoSihat FAQ, question 2](https://infosihat.moh.gov.my/faq.html) expressly allows individuals and organisations to republish its educational media **without amendments**, without obtaining separate consent. Changes to content, design, images or graphics require notification and approval. This is a reuse permission, not public-domain status. Check the credited owner of each item: some portal videos belong to third parties such as TV1, and the portal's general FAQ should not be assumed to clear those rights.

Therefore: preserve a qualifying KKM source video intact, including credits; do not cut intros, translate, dub or edit it under an unmodified-reuse permission. Keep attribution and the FAQ URL with each accepted asset. Assess actual content before assigning it to a category; do not substitute general prevention for practical treatment merely to fill every category.

## Initial research candidates (superseded by implemented coverage above)

- [KKM Bantuan Kecemasan](https://infosihat.moh.gov.my/penerbitan-multimedia/video/item/bantuan-kecemasan.html): explicitly credited to Bahagian Pendidikan Kesihatan, KKM. Download available. Its complete content/duration has not yet been reviewed for a precise category match and no-intro requirement.
- [KKM heat-stroke signs and hot-weather advice for children](https://infosihat.moh.gov.my/penerbitan-multimedia/video/item/tanda-tanda-strok-haba-dan-tip-kekal-sihat-bagi-kanak-kanak-semasa-musim-panas.html): Malaysia-specific, but children/prevention focus is not automatically an adult-hiker treatment tutorial. Not approved.
- [KKM Panduan Semasa Banjir](https://infosihat.moh.gov.my/penerbitan-multimedia/video/item/panduan-semasa-banjir.html): potential flood-safety supplement, not automatically a complete lightning/severe-weather hiking tutorial. Not approved.
- [SAFE STEPS severe bleeding, Bahasa Malaysia](https://www.youtube.com/watch?v=ZPy_0wF49CA).
- [SAFE STEPS broken bones, Bahasa Malaysia](https://www.youtube.com/watch?v=mkJYnPJj5Xc).
- [SAFE STEPS CPR, Bahasa Malaysia](https://www.youtube.com/watch?v=lacWv2RfPzg): not one of the current seven categories, so do not substitute it for an unrelated topic.

[The publisher describes SAFE STEPS as six one-minute first-aid PSAs with Bahasa Malaysia versions](https://www.prulifeuk.com.ph/en/about-us/newsroom/prudence-foundation-launches-safe-steps-first-aid-across-asia/). [Prudential Malaysia also describes the programme](https://www.prudential.com.my/en/about-us/community-investment/education/safe-steps/). No explicit licence for Firebase rehosting, editing and offline caching was verified. Public access/YouTube availability is not that licence. Do not use terms from similarly named, unrelated Safe Steps companies as permission.

## Coverage status

No complete set meeting topic fit, Malaysian suitability, concise presentation and verified redistribution rights has been established for falls/injury, bleeding, sprains, heat exhaustion, snakebite, lost/stranded and severe weather. No candidate has been medically approved by this audit. In particular, a snake-encounter prevention video is not a snakebite treatment tutorial.

## Remaining coverage

Either obtain publisher permission for suitable existing videos (including any required cuts and offline redistribution), accept intact qualifying videos/official-source playback with its limitations, or commission original HikerCircle instructional animations. Original medical instruction would need Malaysian source verification and qualified first-aid review before publication, rather than being represented as an approved clinical tutorial merely because it is newly generated.

After selecting cleared, reviewed replacements: update WHAT TO DO from verified Malaysian guidance, use fresh immutable storage paths and cache versions, record provenance and permission per asset, then validate each video and Android/iOS offline playback. Do not overwrite v1 files under old names or let an updated guide silently play cached US clips.
