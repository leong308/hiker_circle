# Malaysia first-aid guide media retirement

Updated 28 September 2026.

HikerCircle no longer presents downloaded tutorial videos in the First-Aid Guide. The prior video pathway was removed because short awareness clips did not provide consistent, condition-specific instructions across every emergency category.

## Current implementation

- All seven categories use the same scenario response pattern: choose the observed condition, open a focused action sheet, follow five ordered actions, review unsafe actions to avoid, and open the cited source in the in-app browser.
- The guide contains 36 scenarios covering falls and injuries, bleeding, sprains, heat illness, snakebite, lost or stranded hikers, and severe weather.
- The two previously published KKM MP4 objects were removed from Firebase Storage. The `first_aid/videos/` prefix is empty.
- The video player, downloader/cache service, upload scripts, package dependency, and Storage rule were removed.
- When an updated app opens the guide, it deletes the retired `first_aid/videos` application-support cache if an older build downloaded it.

## Guidance sources

The scenario records in `assets/guides/first_aid_guide.json` carry their own source name and HTTPS link. Principal Malaysian or authoritative sources include:

- [Ministry of Health Malaysia snakebite guideline](https://www2.moh.gov.my/moh/resources/Penerbitan/Garis%20Panduan/Garis%20Panduan%20Umum%28KKM%29/Guideline%20Management%20Of%20Snakebite.pdf)
- [KKM InfoSihat hot-weather guidance](https://infosihat.moh.gov.my/cuaca-panas.html)
- [METMalaysia weather education](https://www.met.gov.my/en/pendidikan/fenomena-cuaca/)
- [Malaysian Medical Gazette first aid and basic life support](https://www.mmgazette.com/first-aid-basic-life-support-dr-khoo-yoong-khean/)

International clinical and outdoor-safety references are used where a precise Malaysian public guide was not available. These include the World Health Organization, CDC/NIOSH, NHS, American Red Cross, US National Weather Service, and US National Park Service. References are supporting guidance, not a claim that HikerCircle replaces professional training or emergency care.

## Verification

Automated tests require every category to have at least four scenarios, every scenario to contain exactly five ordered actions and at least one unsafe action to avoid, every reference to use HTTPS, and the manifest to contain no video path, download URL, or MP4 reference.
