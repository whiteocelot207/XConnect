# XConnect (iOS) v0.5

App iPhone untuk menampilkan peta Indonesia, data motor, musik, dan foto di dash TFT Yamaha (NMAX/XMAX)
lewat ExternalAccessory (iAP) `com.garmin.navilite.data`, plus data CCU lewat BLE.
(Dulu bernama NmaxConnect. Bundle ID sengaja tetap `id.nmaxconnect.app` agar pengaturan lama tidak hilang.)

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
