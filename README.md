# XConnect (iOS) v0.8

App iPhone untuk menampilkan peta Indonesia, data motor, musik, dan foto di dash TFT Yamaha (NMAX/XMAX)
lewat ExternalAccessory (iAP) `com.garmin.navilite.data`, plus data CCU lewat BLE.
(Dulu bernama NmaxConnect. Bundle ID sekarang `id.xconnect.app` (app baru, terpisah dari yang lama; pindahkan pengaturan lewat Cadangkan dan pulihkan).)

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
  (bawaan 50%: volume 70% menjadi 35%) lewat MPVolumeView tersembunyi, lalu mengembalikannya. Sesi audio selalu playback + mixWithOthers (tidak berpindah kategori), tidak dilepas, dan audio senyap dijaga hidup selama navigasi, jadi saat suara berbunyi sesi audio tidak berubah sama sekali. Log mencatat perubahan rute audio dan permintaan "audio lain diam" untuk menelusuri bila musik masih berhenti. Bisa diatur: nyala/mati, kecilkan musik atau tidak, volume suara, tombol "Coba suara".
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
- **Ukuran huruf kotak data**: Pengaturan > Kotak data > Ukuran huruf (kotak besar dan kecil, 0.5x - 1.5x). Isi kotak
  otomatis dikecilkan bila tidak muat, jadi tidak ada lagi teks terpotong atau keluar kotak. Susunan kotak cuaca
  menyesuaikan tinggi kotak.
- **Data HP di latar belakang**: mode latar belakang `audio` + audio senyap (kategori playback, mixWithOthers) selama
  dash tersambung, supaya volume HP dan data HP lain tetap berubah saat app tidak dibuka atau layar terkunci.
  Bisa dimatikan di Pengaturan > Motor dan koneksi > "Jaga data HP tetap hidup di latar belakang".
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
- **Tautan Google Maps dibuka seperti peramban PC**: bila alamat akhir tidak memuat koordinat, app membuka tautan di WKWebView
  tersembunyi (identitas peramban PC), menunggu JavaScript Google mengubah alamat menjadi /maps/place/…/@lat,lon/…!3d…!4d…,
  lalu membaca koordinatnya (maks. 14 dtk). Pencarian nama (Apple Maps/OSM) hanya cadangan bila langkah ini gagal.
- **Tautan Google Maps berisi teks saja** (`google.com/maps?q=NAMA,+ALAMAT&ftid=…`, tanpa koordinat): teks `q=` dari alamat akhir
  dicari lewat Apple Maps + OpenStreetMap, dipilih yang namanya paling cocok (bukan hasil pertama), cadangan geocoder alamat.
  Subtitle tujuan menampilkan sumber dan jarak dari posisi Anda untuk diperiksa.
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
- **Update**: workflow menerbitkan `source.json`; tombol "Tambah sumber ke SideStore/AltStore" menambahkannya
  sekali, lalu update dipasang dari SideStore dengan bundle ID yang benar.
- **Cuaca** diambil juga saat preview Home tampil (sebelumnya hanya saat dash tersambung).

## Yang baru di 0.4
- **Ganti nama** jadi XConnect.
- **Update dari dalam app**: Pengaturan > Update aplikasi. Isi `pemilik/nama-repo`. Setiap build GitHub Actions
  menerbitkan Release (`build-<nomor>`, berisi XConnect.ipa). App membandingkan nomor build lalu membuka
  SideStore/AltStore dengan URL IPA terbaru (satu ketukan konfirmasi). Repo harus **public** agar app bisa membacanya.
- **Link CCU (BLE)**: ID+passkey dari iAP `com.yconnect.data` → scan `YCCU_<id>` → auth → langganan data.
  Aki, ODO, suhu mesin/udara, RPM tampil di kotak data. Izin Bluetooth sekarang muncul di Pengaturan iOS.
  BELUM PERNAH diuji di motor; semua langkah dicatat di log (`CCU BLE: …`).
- **Koneksi**: frame dikirim ulang sampai 3x bila ACK dash terlambat (sebelumnya langsung putus di 2 dtk);
  watchdog bila render macet.
- **Tombol stang tanpa delay**: klik pertama langsung jalan, klik 2x membatalkan lalu menjalankan aksi 2x.
  Di layar Musik: 1x = volume, 2x = ganti tampilan.
- **Kotak data fleksibel**: Pengaturan > Kotak data. Tata letak 1 besar + 2/4 kecil atau 4 kecil, tiap kotak
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
4. Pasang pertama kali dengan Sideloadly; update berikutnya dari app (SideStore/AltStore).
