# Vehicle image credits

All vehicle photos in the `VehicleImages` static resource come from **Wikimedia Commons** and are reused under the
licence shown. Licences were read from each file's Commons metadata (`LicenseShortName`) at download time.

**Changes made:** every photo was centre-cropped to a 16:10 aspect ratio and resized to 960 x 600 px (JPEG). Under
CC BY-SA these cropped versions are shared under the same licence as the original. CC0 and public-domain photos need
no attribution, but are credited anyway.

**Where credit is shown:** the vehicle detail page shows "Photo: author / licence", linked to the Commons file page
(`c-vehicle-photo`, hero variant). The machine-readable list is `force-app/main/default/lwc/vehiclePhoto/credits.js`.

**How images are referenced:** `Vehicle__c.Image_URL__c` holds the bare file name (for example `tata-punch.jpg`).
`c-vehicle-photo` resolves it to the static resource URL. Full `https://` URLs and site-relative paths still work.
Anything else, and any image that fails to load, shows the "Photo coming soon" placeholder.

| Vehicle record(s) | File | Commons source | Author | Licence | Match notes |
|---|---|---|---|---|---|
| Maruti Swift 2023 (VEH-0006) | `maruti-swift.jpg` | [SUZUKI SWIFT XR-Limited 2018 Front.jpg](https://commons.wikimedia.org/wiki/File:SUZUKI_SWIFT_XR-Limited_2018_Front.jpg) | Suzuki-Ham | CC0 | Japanese-market 2018 Suzuki Swift: same 3rd-generation body as the Indian Maruti Swift (2018-2024) |
| Tata Punch 2024 (VEH-0009) | `tata-punch.jpg` | [2021 Tata Punch Creative (India) front view 01.png](https://commons.wikimedia.org/wiki/File:2021_Tata_Punch_Creative_(India)_front_view_01.png) | Athira Murali | CC BY 3.0 | Exact model |
| Hyundai i20 2023 (VEH-0008) | `hyundai-i20.jpg` | [Hyundai i20 (BC3) 1X7A6488.jpg](https://commons.wikimedia.org/wiki/File:Hyundai_i20_(BC3)_1X7A6488.jpg) | Alexander Migl | CC BY-SA 4.0 | Exact model |
| Maruti Dzire 2023 (VEH-0017) | `maruti-dzire.jpg` | [Maruti Suzuki Dzire VXi VVT.JPG](https://commons.wikimedia.org/wiki/File:Maruti_Suzuki_Dzire_VXi_VVT.JPG) | Biswarup Ganguly | CC BY 3.0 | Exact model |
| Honda Amaze 2022 (VEH-0013) | `honda-amaze.jpg` | [Honda Amaze (front).png](https://commons.wikimedia.org/wiki/File:Honda_Amaze_(front).png) | Agratsa | CC BY-SA 4.0 | Exact model |
| Maruti Ertiga 2023 (VEH-0012) | `maruti-ertiga.jpg` | [2022 Maruti Suzuki Ertiga LXi.jpg](https://commons.wikimedia.org/wiki/File:2022_Maruti_Suzuki_Ertiga_LXi.jpg) | Ramakrishna Mission Vidyapith | Public domain | Exact model |
| Kia Sonet 2024 (VEH-0018) | `kia-sonet.jpg` | [Kia Sonet front view (India) 01.png](https://commons.wikimedia.org/wiki/File:Kia_Sonet_front_view_(India)_01.png) | DriveSpark | CC BY 3.0 | Exact model |
| Honda City 2022 (VEH-0005) | `honda-city.jpg` | [2021 Honda City 1.5 GN2 (20211117).jpg](https://commons.wikimedia.org/wiki/File:2021_Honda_City_1.5_GN2_(20211117).jpg) | オーバードライブ83 | CC BY-SA 4.0 | 5th-gen (GN) City, 2021 Thai-market car: same generation as the 2022 Indian City |
| Maruti Brezza 2022 (VEH-0002) | `maruti-brezza.jpg` | [2026 Maruti Brezza Rear Quarter Static.jpg](https://commons.wikimedia.org/wiki/File:2026_Maruti_Brezza_Rear_Quarter_Static.jpg) | Blthippeswamy | CC0 | Rear three-quarter view (only CC0 photo of the 2022 model found) |
| Hyundai Verna 2023 (VEH-0014) | `hyundai-verna.jpg` | [Hyundai Verna SX Turbo 03.jpg](https://commons.wikimedia.org/wiki/File:Hyundai_Verna_SX_Turbo_03.jpg) | Siddharth Antre | CC BY-SA 3.0 | Exact model |
| Kia Seltos 2023 (VEH-0001) | `kia-seltos.jpg` | [Kia Seltos IMG 9152.jpg](https://commons.wikimedia.org/wiki/File:Kia_Seltos_IMG_9152.jpg) | Alexander-93 | CC BY-SA 4.0 | Exact model |
| Tata Nexon EV 2024 (VEH-0007) | `tata-nexon-ev.jpg` | [2020 Tata Nexon EV (India) front view.png](https://commons.wikimedia.org/wiki/File:2020_Tata_Nexon_EV_(India)_front_view.png) | DriveSpark | CC BY 3.0 | Exact model |
| Hyundai Creta 2023 (VEH-0000) | `hyundai-creta.jpg` | [2021 Hyundai Creta SX(O) CRDi (India) front view.jpg](https://commons.wikimedia.org/wiki/File:2021_Hyundai_Creta_SX(O)_CRDi_(India)_front_view.jpg) | Dairokkan9 | CC BY-SA 4.0 | 2nd generation (2020+); same body as 2023 before the 2024 facelift |
| Kia Carens 2024 (VEH-0004) and 2025 demo (VEH-0020) | `kia-carens.jpg` | [Kia Carens 2024 Model.jpg](https://commons.wikimedia.org/wiki/File:Kia_Carens_2024_Model.jpg) | Ganesh Mohan T | CC BY-SA 4.0 | Exact model |
| MG ZS EV 2024 (VEH-0015) | `mg-zs-ev.jpg` | [MG ZS EV Facelift 1X7A5867.jpg](https://commons.wikimedia.org/wiki/File:MG_ZS_EV_Facelift_1X7A5867.jpg) | Alexander Migl | CC BY-SA 4.0 | Facelifted ZS EV, European-market plate |
| Mahindra Scorpio-N 2023 (VEH-0019) | `mahindra-scorpio-n.jpg` | [2024 Mahindra Scorpio Z8L front.jpg](https://commons.wikimedia.org/wiki/File:2024_Mahindra_Scorpio_Z8L_front.jpg) | LuvsMG481 | CC BY-SA 4.0 | Exact model |
| Toyota Innova Crysta 2023 (VEH-0003) | `toyota-innova-crysta.jpg` | [Toyota Innova Crysta 2.4 Z front right.jpg](https://commons.wikimedia.org/wiki/File:Toyota_Innova_Crysta_2.4_Z_front_right.jpg) | Premnath Kudva | CC BY-SA 4.0 | Exact model |
| Mahindra XUV700 2023 (VEH-0010) | `mahindra-xuv700.jpg` | [2021 Mahindra XUV700 2.2 AX7 (India) front view.png](https://commons.wikimedia.org/wiki/File:2021_Mahindra_XUV700_2.2_AX7_(India)_front_view.png) | DriveSpark | CC BY 3.0 | Exact model |
| Toyota Fortuner 2022 (VEH-0011) | `toyota-fortuner.jpg` | [2015 Toyota Fortuner (New Zealand).jpg](https://commons.wikimedia.org/wiki/File:2015_Toyota_Fortuner_(New_Zealand).jpg) | NZ Car Freak | CC BY-SA 4.0 | Exact model |
| BMW 3 Series 2023 (VEH-0016) | `bmw-3-series.jpg` | [BMW 3 SERIES SEDAN (G20) China (2).jpg](https://commons.wikimedia.org/wiki/File:BMW_3_SERIES_SEDAN_(G20)_China_(2).jpg) | Dinkun Chen | CC BY-SA 4.0 | G20 3 Series, Chinese-market plate |

Licence texts: [CC0](https://creativecommons.org/publicdomain/zero/1.0/) -
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) -
[CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) -
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) -
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
