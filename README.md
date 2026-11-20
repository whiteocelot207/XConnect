# XConnect (iOS) v0.8.2+

App iPhone untuk menampilkan peta Indonesia, data motor, musik, dan foto di dash TFT Yamaha (NMAX/XMAX)
lewat ExternalAccessory (iAP) `com.garmin.navilite.data`, plus data CCU lewat BLE.
(Dulu bernama NmaxConnect. Bundle ID sekarang `id.xconnect.app` (app baru, terpisah dari yang lama; pindahkan pengaturan lewat Cadangkan dan pulihkan).)

## Routing, pratinjau rute, dan tautan Google Maps
- **Routing hanya Valhalla.** Pilihan Apple Maps (MapKit) sudah dihapus (`MapKitRouter.swift` dan pemilih sumber di Pengaturan).
  Batas kecepatan maksimal, jalan utama, tanjakan, dan lainnya diatur di Pengaturan > Rute dan pencarian. Suara petunjuk tetap
  bahasa Indonesia dan angka Romawi dibaca sebagai angka.
- **Pratinjau peta di pemilihan rute**: setelah memilih tempat atau menempel tautan, kotak rute menampilkan peta kecil berisi semua
  rute (terpilih biru, alternatif abu-abu) dan tujuan (`Views/RoutePreviewMap.swift`). Ketuk garis rute lain untuk memilihnya,
  ketuk di tempat lain untuk membuka peta penuh. BELUM DIUJI di perangkat.
- **Tautan Google Maps lebih cepat** (`Nav/MapsLink.swift`): tahap cepat mengikuti pengalihan tautan pendek satu per satu dengan
  membaca header Location saja (tanpa mengunduh halaman Google) dan berhenti begitu koordinat terlihat. Bila tautan hanya berisi
  nama tempat, nama itu langsung dicari lewat Apple + OpenStreetMap yang berjalan bersamaan dan diterima bila namanya cocok hampir
  seluruhnya (skor >= 0,75). Cara lama (mengunduh halaman, WKWebView tersembunyi, ID tempat, pencarian longgar) hanya dipakai
  bila cara cepat tidak meyakinkan. Subtitle tujuan menampilkan sumbernya; "(dari nama)" berarti titik dicari dari nama,
  jadi periksa lokasinya bila ada banyak cabang dengan nama sama.
- **Tautan Google Maps dibuka seperti peramban PC** (cadangan): bila alamat akhir tidak memuat koordinat, app membuka tautan di
  WKWebView tersembunyi, menunggu JavaScript Google mengubah alamat menjadi /maps/place/…/@lat,lon/…!3d…!4d…, lalu membaca
  koordinatnya (maks. 14 dtk).
- **Rute skuter**: opsi Valhalla `motor_scooter` kini use_primary 1.0, use_hills 0, top_speed 80 (bawaan 0,5 / 0,5 / 45 km/j
  membuat rute memutar lewat jalan kecil dan estimasi waktu terlalu lama). Ada tombol bawaan XConnect (80 km/j) dan bawaan
  Valhalla (45 km/j); profil ikut tersimpan di Cadangkan dan pulihkan.

## Bensin ala NConnect (baru)
- Konsumsi untuk sisa bensin: **rata-rata konsumsi di dash (CCU)** bila terbaca, lalu **konsumsi Anda sendiri 30 hari terakhir**
  (dihitung dari pemakaian terukur dash), lalu nilai bawaan 30 km/L. Riwayat pengisian lama dihapus dari perhitungan karena melingkar
  (liter "Baru diisi" dihitung dari estimasi sendiri, bukan dari pompa).
- Peringatan oranye di layar Motor bila motor menempuh lebih dari satu tangki tanpa app terhubung; hilang saat "Baru diisi" atau atur manual.
- **Pengaturan > Motor dan BBM > Cari byte dari angka di dash**: ketik rata-rata BBM yang tampil di dash, app mencari byte paket id 1
  yang cocok, ketuk kandidat untuk memakainya. Letak byte masih belum diketahui; BELUM DIUJI di motor.

## Yang baru di 0.8.2
- **Tekan tahan di layar Musik** (Pengaturan > Kontrol pada motor > Tekan tahan): tahan tombol atas = lagu berikutnya, tahan tombol
  bawah = lagu sebelumnya, sekali per tahan; muncul pesan singkat di dash. Lama tahan bisa diatur (300-2000 ms, bawaan 700).
  Tahan dikenali dari tekan berulang arah sama (dash mengulang tekan saat tombol ditahan) selama >= durasi tahan, minimal 3 tekan.
  Karena itu klik 2x di layar Musik (ganti tampilan) kini menunggu 0,4 dtk untuk memastikan itu bukan awal tahan; matikan
  "Tahan = lagu berikutnya/sebelumnya" untuk kembali ke perilaku lama. BELUM DIUJI di motor: bila tidak bereaksi, kirim baris Log
  "Tombol: ..." saat menahan tombol (tiap tekan dicatat dengan jarak waktunya).
- **Volume HP <-> dash**: volume yang diubah dari HP kini masuk ke dash dan klik stang berikutnya dihitung dari volume yang benar.
  Penyebab: `outputVolume` bisa basi dan bacaan 1 dtk menimpa nilai baru. Kini volume dibaca dari KVO, notifikasi volume sistem, dan
  slider MPVolumeView; bacaan `outputVolume` hanya dipakai bila nilainya berubah. Perubahan dari luar langsung dikirim ke dash dan
  tercatat di Log ("Volume sistem berubah dari luar"). Langkah stang dibulatkan ke 16 langkah volume iOS.
- **Info pojok layar Musik** kini memuat nama data: "Kecepatan 40 km/h", "Jam 12:30" (nama abu-abu kecil, nilai tebal); mengecil
  otomatis bila tidak muat.
- **Sisa bensin memakai konsumsi dari CCU** (Pengaturan > Motor dan BBM > Konsumsi BBM dari CCU): pilih byte paket data CCU (id 1)
  yang berisi rata-rata konsumsi, lebar (1/2 byte), satuan (km/L, L/100 km, L/km), dan pembagi; "Terbaca sekarang" menampilkan
  hasilnya untuk dicocokkan dengan angka di dash. Urutan sumber: CCU, riwayat pengisian, nilai bawaan. Sisa bensin juga kini berkurang
  bertahap (tiap ODO bertambah, memakai konsumsi saat itu), bukan dihitung ulang dari seluruh jarak sejak isi dengan konsumsi terbaru.
  Letak byte konsumsi di data CCU belum diketahui: cari lewat Data mentah CCU.
- **Sambung ulang saat app diminimize/dibuka**: sambung ulang pertama dalam 0,7 dtk (dulu 3 dtk); ACK dash yang terlambat tidak
  langsung menutup sesi selama 10 dtk setelah berpindah latar/depan; aksesori yang hilang sesaat tidak langsung menutup sesi
  (dicek lagi setelah 2,5 dtk); pratinjau Home ditahan 2,5 dtk setelah app dibuka supaya thread utama tidak sibuk; ada tambahan waktu
  eksekusi saat masuk latar belakang. Log kini mencatat keadaan app saat sesi tertutup. Penyebab pastinya belum terbukti: bila masih
  putus, kirim Log dari saat minimize sampai tersambung lagi.

## Yang baru di 0.8.1 (perbaikan hang)
- **Dash macet setelah klik stang**: dari Log terlihat data CCU (yang diterima di thread utama) kadang berhenti 4-7 dtk. Penyebab yang
  dicurigai: tiap frame (hingga 10x/dtk) thread utama membaca volume, rute audio, dan jaringan seluler, yang semuanya IPC ke layanan
  sistem dan bisa tertahan saat musik diputar atau volume berubah. Kini nilai itu dibaca di antrean latar (1x/dtk) dan hanya disalin
  saat menggambar frame. Volume dari klik stang langsung memperbarui nilai cache.
- **Log baru**: "Thread utama tertahan N dtk" bila thread utama macet lebih dari 1 dtk; "App aktif / ke latar belakang / kembali ke
  depan" beserta status sesi dash, untuk menelusuri sambung ulang saat app dibuka dari latar belakang.
- Kategori sesi audio tidak disetel ulang bila sudah sama (setCategory berulang tiap app aktif bisa memicu perubahan rute Bluetooth).
- **Ikon bar atas dash**: XConnect kini mengirim status ponsel ke CCU (ctrl 316, format dari nmax_connect `docs/bike-protocol.md` §6.6):
  baterai HP + cas, volume, sinyal, headset, panggilan, suhu. Dikirim saat berubah dan diulang tiap 20 dtk. Log: `CCU: status ponsel → 01 3c …`.
  Catatan: iOS tidak punya API jumlah bar sinyal, jadi diisi 4 bar bila ada jaringan data, "tanpa sinyal" bila ada SIM tanpa jaringan.
  Ikon headset menyala bila keluaran audio memakai Bluetooth atau headphone.
- Ikon pesan: di iOS datang lewat ANCS (iPhone → Pengaturan → Bluetooth → ⓘ YCCU… → Bagikan Notifikasi Sistem), bukan dari app.
- **Tombol stang berhenti merespons (hang)**: menurut docs/protocol/link-a-dash.md, tepat setelah tiap tekan (cmd 51/52) app harus
  mengirim cmd 14 (flag 1, `07 1A ...`), kalau tidak hanya tekanan pertama yang sampai. XConnect hanya mengirimnya lewat label zoom
  saat zoom berubah, jadi klik volume di layar Musik, ganti tampilan, dan layar Tes tombol membuat tombol berhenti. Kini label dikirim
  ulang setelah tiap tekan bila belum terkirim.
- Status ponsel (cmd 316): bit 0 flag selalu 1 (seperti capture app resmi). Status panggilan dikirim terpisah (cmd 308: 1 = ada, 2 = selesai).
- **Bahasa dash (eksperimen)**: Pengaturan > Eksperimen dan log. Mengirim cmd 12 dan menjawab permintaan bahasa CCU (cmd 11). Dugaan: jam
  12/24 jam di bar atas dash mengikuti bahasa. Bawaan tidak dikirim.
- **Klik 2x di layar Musik**: pembatalan volume klik pertama dihitung dari volume sistem yang belum terbarui, sehingga tiap klik 2x
  menggeser volume satu langkah. Kini memakai target volume terakhir (selama 1,5 dtk) sebagai dasar.
- Belum ada: format jam 24 jam di dash (tidak ada di dokumen protokol; kemungkinan pengaturan di dash sendiri).

## Yang baru di 0.8
- **Teks petunjuk arah**: arah belok sudah diwakili ikon, jadi panel hijau kini hanya menulis tujuan belokan lalu jarak:
  "Ke Jalan Contoh" / "65 m" (sebelumnya "Belok kanan / 65 m / ke Jalan Contoh"). Di bundaran: "Ambil jalan keluar ke 3" / "65 m".
  Berlaku untuk semua jenis belokan, di layar Peta + data dan Speedometer, dan di layar ponsel. Bila belokan tidak punya
  nama jalan, dipakai teks arah ("Belok kanan"). Kalimat lengkap tetap ada sebagai data: "Dalam 65 meter, belok kanan ke Jalan Contoh",
  "Dalam 65 meter, di bundaran, ambil jalan keluar ke 3" (dipakai untuk suara dan teks kecil di tab Navigasi).
- **Suara petunjuk arah** (Pengaturan > Rute dan pencarian > Suara petunjuk arah): bahasa Indonesia (suara id-ID iOS),
  diumumkan di sekitar 300 m (500 m bila lebih dari 60 km/j) dan 100 m sebelum belokan, plus "Navigasi dimulai", "Menghitung ulang rute",
  dan "Anda telah tiba di tujuan". Saat berbunyi, musik/audio app lain dikecilkan (ducking, seperti Google Maps) lalu kembali ke volume
  semula setelah selesai. Ducking bawaan iOS terlalu kuat, jadi app menurunkan volume ponsel sendiri ke persentase yang diatur
  (bawaan 50%: volume 70% menjadi 35%) lewat MPVolumeView tersembunyi, lalu mengembalikannya. Suara petunjuk dibuat sebagai audio terpisah (AVSpeechSynthesizer.write -> AVAudioEngine) dan diperkeras sebesar kebalikan penurunan volume (50% -> 2x, dibatasi agar tidak pecah), jadi tetap sekeras volume semula. Sesi audio selalu playback + mixWithOthers (tidak berpindah kategori), tidak dilepas, dan audio senyap dijaga hidup selama navigasi, jadi saat suara berbunyi sesi audio tidak berubah sama sekali. Log mencatat perubahan rute audio dan permintaan "audio lain diam" untuk menelusuri bila musik masih berhenti. Bisa diatur: nyala/mati, kecilkan musik atau tidak, volume suara, tombol "Coba suara".
  Ada juga tombol speaker di kotak rute (tab Navigasi) untuk menyalakan/membisukan cepat.
- **Nama jalan dibaca benar**: angka Romawi pada nama jalan diucapkan sebagai angka ("Maligi I" dibaca "Maligi satu", II = dua, IV = empat,
  dst.), dan singkatan dibuka: Jl. = Jalan, Gg. = Gang, Jend. = Jenderal, Prof., Dr., Ir., Kav., No. (hanya untuk suara; tulisan di layar tidak berubah).
- **Simulasi navigasi** (tab Navigasi, kotak rute): tombol "Simulasikan navigasi" tersedia di pratinjau rute dan saat navigasi berjalan
  (di samping "Hentikan navigasi"). Posisi buatan berjalan di sepanjang rute (20/40/80/150 km/j), mengalir ke dash, suara, dan peta
  seperti berkendara sungguhan; GPS asli diabaikan dan perjalanan tidak dicatat. "Hentikan simulasi" kembali ke pratinjau rute.

- **Isi kotak estimasi dapat dipilih** (Pengaturan > Peta di dasbor > Kotak estimasi): estimasi jarak (sisa jarak), estimasi durasi
  perjalanan (sisa waktu, mis. "12 mnt"), dan estimasi waktu sampai (jam tiba). Boleh dipilih satu, dua, atau ketiganya
  (urutan: jarak · durasi · jam tiba). Bawaan: jarak dan jam tiba. Bila semuanya dimatikan, kotak disembunyikan.

## Yang baru di 0.7
- **Ikon aplikasi** XConnect (Sources/Assets.xcassets/AppIcon). Ikon di source.json SideStore/AltStore ikut memakainya.
- **Ikon putar balik** kini benar: putar balik kanan menampilkan panah ke kanan, putar balik kiri ke kiri
  (sebelumnya terbalik; lalu lintas Indonesia di kiri, jadi putar balik yang umum adalah ke kanan).
- **Nama jalan di petunjuk arah**: panel hijau kini memuat baris "ke <nama jalan>" (jalan tujuan belokan dari Valhalla),
  juga di layar Speedometer.
- **Lebar kotak hijau menyesuaikan isi teks** (panel belokan dan kotak jarak + ETA), tidak lagi tetap.
  Sudut kotak jarak + ETA kini sama seperti panel belokan (tidak terlalu bulat).
- **Ukuran huruf kotak data**: Pengaturan > Kartu Data > Ukuran huruf (kotak besar dan kecil, 0.5x - 1.5x). Isi kotak
  otomatis dikecilkan bila tidak muat, jadi tidak ada lagi teks terpotong atau keluar kotak. Susunan kotak cuaca
  menyesuaikan tinggi kotak.
- **Data HP di latar belakang**: mode latar belakang `audio` + audio senyap (kategori playback, mixWithOthers) selama
  dash tersambung, supaya volume HP dan data HP lain tetap berubah saat app tidak dibuka atau layar terkunci.
  Bisa dimatikan di Pengaturan > Koneksi > "Jaga data HP tetap hidup di latar belakang".
- **Kurangi delay**:
  - frame yang menunggu ACK dash lebih dari 0,15 dtk dibuang dan digambar ulang dengan data terbaru (dulu frame lama
    tetap dikirim, jadi peta/angka tertinggal sepanjang waktu tunggu ACK);
  - posisi di peta digeser searah gerak sejauh kecepatan x (umur GPS + 0,3 dtk), jadi titik motor tidak tertinggal;
  - JPEG di-encode di luar thread utama, kualitas bisa diatur (bawaan 0,7, lebih ringan dari 0,8);
  - frame yang sama persis dengan sebelumnya tidak dikirim (kecuali tiap 1 dtk), mengurangi beban Bluetooth;
  - label zoom dikirim langsung saat tombol ditekan, tidak menunggu frame berikutnya.
- **Tombol stang**: jendela klik 2x bisa sampai 2000 ms. Byte dari dash yang dibuang parser (bukan paket NaviLite sah)
  kini dicatat di Log beserta isinya. Klik tahan: BELUM bisa, dash tidak mengirim apa pun lewat iAP saat tombol
  ditahan (lihat catatan di bawah).

### Catatan klik tahan dan klik 2x
Semua paket dari dash di protokol NaviLite (`com.garmin.navilite.data`) dan CCU (`com.yconnect.data`) dicatat di Log.
Bila klik tahan tidak menghasilkan baris apa pun, dash tidak mengirimnya ke iPhone lewat kedua protokol itu, jadi app tidak
punya sinyal untuk dibaca. Untuk klik 2x, bandingkan selisih ms di Log: bila dua tekan cepat tercatat berjarak lebih dari
jendela, penundaannya ada di sisi dash atau Bluetooth (bukan di app).

## Yang baru di 0.6
- **Profil rute dapat diatur** (Pengaturan > Rute dan pencarian > Profil rute): preferensi jalan utama, batas kecepatan maksimal,
  tanjakan, gang, jalan setapak, tol, jalan bebas hambatan, feri, dan rute terpendek. Dikirim ke Valhalla sebagai `costing_options`
  dan ikut tersimpan di Cadangkan dan pulihkan. Ada tombol bawaan XConnect (80 km/j) dan bawaan Valhalla (45 km/j).
- **Rute skuter**: opsi Valhalla `motor_scooter` kini use_primary 1.0, use_hills 0, top_speed 80 (bawaan 0,5 / 0,5 / 45 km/j
  membuat rute memutar lewat jalan kecil dan estimasi waktu terlalu lama).
- **Volume HP di dash**: sesi audio kini diaktifkan (ambient + mixWithOthers, tidak mengganggu musik) karena iOS hanya
  memperbarui `outputVolume` saat sesi aktif. Arah kompas kosong sampai ada arah gerak; jaringan memakai SIM data.
- **Tautan Google Maps** (`maps.app.goo.gl/...`): dicoba dengan identitas peramban desktop lebih dulu, lalu iPhone; juga
  membaca ID tempat (ftid/cid), alamat tersembunyi di isi halaman, dan pola koordinat baru. Bila masih gagal, pesan
  errornya memuat host akhir dan jumlah pengalihan: kirim pesan itu.
- **Rute alternatif**: pratinjau menampilkan Tercepat + hingga 2 alternatif (pilih sebelum Mulai). Bawaan tetap tercepat.
- **Tab Navigasi**: daftar pencarian tidak lagi tertutup peta. Saat ada tujuan, kotak rute muncul di atas
  (pilihan rute, Mulai/Batal, Hentikan navigasi, tombol Peta untuk membuka peta). 
- **Posisi di dash**: titik motor (atas-bawah dan kiri-kanan), kotak petunjuk arah, dan kotak estimasi punya slider
  geser sendiri, ada pratinjau di halaman Peta di dasbor dan tombol atur ulang.
- **Nama jalan** di bilah bawah dash tetap tampil saat tidak navigasi (dari GPS, Apple geocoder).
- **Kotak data**: latar kolom kini setinggi layar dengan tepi kiri memudar; kegelapannya bisa diatur (0 = transparan).
- **Data CCU lengkap**: kotak baru DTC, kecepatan CCU, volume HP, output audio, jaringan seluler, tanggal, arah, ketinggian,
  dan "CCU byte 0-23" (data mentah). Halaman "Data mentah CCU" menampilkan semua byte; nilai berubah dicatat di Log.
- **Sapaan**: kata sapaan dan nama diubah di Pengaturan > Tampilan (kotaknya sudah dihapus dari tab Home).
- **Format jam** 12/24 jam untuk jam dan ETA yang digambar app.
- **Layar awal** saat motor dinyalakan bisa dipilih; layar baru **Tes tombol** (aktif/nonaktif seperti layar lain).
- **Tombol stang**: jendela klik 2x bisa diatur (300-1200 ms); tiap tekan masuk Log. Perintah media (next/prev/OK,
  tahan next/prev) dan perubahan volume dicatat di Log lewat pemantau pemutar musik.

## Yang baru di 0.5
- **CCU**: bila CCU menolak cmd 294 (error `01 26 01` di log), app langsung langganan data server 1248 (id 1 dan 72).
  Sesi BLE tidak lagi diputus saat dash membuka ulang sesi iAP. Perlu dites lagi, kirim log.
- **Tombol stang**: log kini mencatat payload dan selisih waktu tiap tekan; jendela klik 2x jadi 0,7 dtk.
  Volume memakai `AVAudioSession.outputVolume` + MPVolumeView yang dibuat saat dash tersambung.
- **Peta**: posisi titik motor kini berlaku juga tanpa rute; ikon belokan digeser ke atas-kanan; ukuran pil ETA
  punya slider sendiri.
- **Kotak data**: lapisan hampir hitam di belakang kolom kotak; nilai kotak kecil tidak lagi mepet bawah.
- **Musik**: latar sampul memakai blur Gaussian (Core Image), bukan lagi pembesaran 24 px.
- **Info pojok layar**: Speedometer, Musik, dan Foto punya pilihan data kiri/kanan atas (termasuk Kosong).
- **Foto**: gambar diisikan ke area yang terlihat dan ada slider geser atas/bawah.
- **Cadangkan dan pulihkan**: Pengaturan > Cadangkan dan pulihkan (file JSON).
- **Tautan Google Maps**: seluruh rantai pengalihan tautan pendek diperiksa (bukan hanya alamat akhir).
- **Update**: workflow menerbitkan `source.json`; tombol "Tambah sumber ke ..." menambahkannya
  sekali, lalu update dipasang dari SideStore, AltStore, atau LiveContainer dengan bundle ID yang benar.
- **Update lewat LiveContainer**: pilih "LiveContainer" di Pengaturan > Tentang. Tombol Pasang memakai
  `livecontainer://install?url=<IPA>` dan tombol Tambah sumber memakai `livecontainer://source?url=<source.json>`
  (tab Sources, LiveContainer 3.7+). Bila bundle ID sudah ada, pilih Ganti agar data app tetap. Bila XConnect
  berjalan di dalam LiveContainer, pakai mode multitasking atau LiveContainer kedua.
- **Cuaca** diambil juga saat preview Home tampil (sebelumnya hanya saat dash tersambung).

## Yang baru di 0.4
- **Ganti nama** jadi XConnect.
- **Update dari dalam app**: Pengaturan > Tentang. Isi `pemilik/nama-repo`. Setiap build GitHub Actions
  menerbitkan Release (`build-<nomor>`, berisi XConnect.ipa). App membandingkan nomor build lalu membuka
  SideStore/AltStore/LiveContainer dengan URL IPA terbaru (satu ketukan konfirmasi). Repo harus **public** agar app bisa membacanya.
- **Link CCU (BLE)**: ID+passkey dari iAP `com.yconnect.data` → scan `YCCU_<id>` → auth → langganan data.
  Aki, ODO, suhu mesin/udara, RPM tampil di kotak data. Izin Bluetooth sekarang muncul di Pengaturan iOS.
  BELUM PERNAH diuji di motor; semua langkah dicatat di log (`CCU BLE: …`).
- **Koneksi**: frame dikirim ulang sampai 3x bila ACK dash terlambat (sebelumnya langsung putus di 2 dtk);
  watchdog bila render macet.
- **Tombol stang tanpa delay**: klik pertama langsung jalan, klik 2x membatalkan lalu menjalankan aksi 2x.
  Di layar Musik: 1x = volume, 2x = ganti tampilan.
- **Kotak data fleksibel**: Pengaturan > Kartu Data. Tata letak 1 besar + 2/4 kecil atau 4 kecil, tiap kotak
  bisa diisi data CCU/HP/cuaca. Warna baru (gradasi + nilai berwarna).
- **Peta**: lebar garis rute + tepi putih, ukuran titik motor, lingkaran, posisi titik, ukuran panel belokan/ETA.
  Titik motor digeser ke tengah pada layar Peta + data.
- **Musik**: latar sampul diperbesar + blur.
- **Favorit**: ganti nama (tekan lama / geser kanan); menu favorit di dash hanya berisi favorit.
- **Bensin**: tombol "Atur sisa bensin manual"; jarak tempuh BBM ikut dihitung ulang dari ODO.
- **Navigasi**: peta hanya ±45% layar. Parser tautan Google Maps diperkuat (judul halaman, ?q=, pola lain).

## Belum (0.5)
Ikon bar atas dash (sinyal/baterai/headset), tombol OK/tahan di stang, pilihan rute alternatif, tata letak tab Navigasi seperti NConnect.

## Belum (lama)
Tombol OK/tahan di stang (perlu log event dash), cuaca kosong, pilihan rute alternatif,
tata letak foto/data overlay.

## Build IPA tanpa Mac
1. Unggah seluruh isi folder ini (termasuk `.github`) ke repo GitHub **public**.
2. Settings > Actions > General > Workflow permissions: **Read and write**.
3. Tab **Actions > iOS IPA > Run workflow**. Hasilnya ada di **Releases** (dan artifact).
4. Pasang pertama kali dengan Sideloadly; update berikutnya dari app (SideStore/AltStore/LiveContainer).


## Perubahan tata letak Pengaturan

- Pengaturan dikelompokkan: Umum (Tampilan, Koneksi, Motor dan BBM), Dasbor di motor (Layar dasbor, Kartu Data, Peta,
  Kontrol pada motor), Navigasi (Rute dan pencarian), Lainnya (Cadangkan, Eksperimen, Tentang).
- Update aplikasi dipindah ke Tentang. Bahasa dash (eksperimen) dipindah ke Eksperimen dan log.
- Layar "Peta saja" dan "Tes tombol" dihapus; "Peta + data" kini bernama "Peta". Kartu cuaca/bensin menjadi "Kartu Data"
  dengan saklar sendiri di Layar dasbor. Pratinjau realtime ada di Layar dasbor, Kartu Data, dan Peta.
- Pilihan kendaraan di Rute dan pencarian dihapus (selalu skuter). Mode peta otomatis: malam 18.00-06.00.

### Pembaruan berikutnya

- **Layar dasbor**: Peta selalu aktif (tidak bisa dimatikan) dan selalu pertama; layar lain bisa diurutkan (Edit di kanan atas).
  Layar awal hanya menawarkan Peta dan layar yang aktif. Info pojok kiri/kanan kini ada di bagian masing-masing
  (Speedometer, Musik, Foto).
- **Teks belokan** di dash dan app tidak lagi memakai awalan "Ke"; suara tetap "belok kiri ke Jalan ...".
  Contoh suara: "Dalam 100 meter, belok kanan ke Jalan Lingkar Luar Jakarta".
- **Cadangan (format 2)** kini memuat semua pengaturan (daftar kunci diambil dari `AppSettings.defaultValues`, jadi
  pengaturan baru otomatis ikut), tempat tersimpan dan favorit, data motor (nama, tipe, tahun, plat, foto, tangki),
  perawatan dan riwayatnya, catatan bensin, dan riwayat perjalanan. Cadangan format 1 lama tetap bisa dipulihkan.
- **Motor dan BBM**: foto motor, tipe (XMAX/NMAX/lainnya), tahun, dan plat nomor diatur di Pengaturan; tombol pensil
  di tab Motor dihapus.

### Pembaruan ketiga

- Daftar tempat "Terakhir" tidak ikut cadangan (saat memulihkan, daftar Terakhir di ponsel dipertahankan).
- Rata-rata BBM di tab Motor (riwayat perjalanan) ditampilkan dalam km/L.
- Ikon belok kini dipusatkan di kotak hijau; kotak jarak/waktu memakai sudut yang sama kotaknya dengan kotak arah.
- Pratinjau di Layar dasbor menampilkan posisi urutan ("Foto · 3 dari 4") dan pindah ke layar yang diaktifkan atau digeser.
