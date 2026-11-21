# Catatan versi

Tambahkan bagian `## x.y.z` baru di paling atas untuk tiap rilis. Aplikasi hanya menampilkan bagian untuk versi yang
terpasang (Pengaturan > Tentang > Yang baru di versi ini); bila suatu versi tidak punya bagian sendiri, yang tampil adalah
bagian terbaru yang tidak lebih baru darinya. Bagian yang sama dipakai sebagai catatan rilis GitHub.

## 0.1.3

### Diperbaiki
- SPBU: pesan error kini tampil tepat di bawah tombol "Cari SPBU terdekat".
- Navigasi: hasil pencarian tempat dan SPBU diurutkan dari yang terdekat.
- Tombol stang (Rumah, Kantor, favorit) kini memilih rute tercepat dari rute yang tersedia.
- Tab Motor: angka ODO, sisa jarak BBM, dan perawatan kini sejajar pada tinggi yang sama.
- Navigasi: di iOS 16 ke atas tombol Tempel tautan memakai kontrol tempel sistem, jadi pertanyaan "Tempel dari app lain" tidak muncul lagi (app tidak bisa mengubah pengaturan iOS itu sendiri).
- Teks bahasa Inggris: contoh di Perizinan dan perawatan beracuan waktu kini "driver's license", bukan "SIM" yang bahasa Indonesia.
- SPBU: semua server pencarian ditanya bersamaan (jauh lebih cepat), hasil disimpan sementara, dan daftar kini menampilkan jarak ke tiap SPBU.
- Dash: menu SPBU diisi dari cache yang disiapkan saat dash tersambung, jadi tidak lagi gagal mendapatkan data dari HP.
- Navigasi: mengetuk SPBU (atau hasil lain) selalu membuka pilihan rute dulu.
- Perawatan: "Ingatkan sebelum servis" sekarang kolom isian kilometer, bukan tombol plus/minus.
- SPBU: pencarian kini beralih ke server cadangan dan memperluas radius (sampai 25 km), serta membedakan "server sibuk" dari "tidak ada SPBU di dekat".
- Teks Perizinan dan perawatan: contoh sekarang SIM, bukan STNK.
- Pengaturan awal/Pengaturan: memilih motor lain kini hanya menampilkan satu kolom "Nama motor", bukan dua.
- App langsung tertutup setelah dibuka (banner melayang kekurangan data).
- Pengaturan awal: izin Bluetooth tidak lagi muncul sendiri saat app pertama dibuka; baru diminta saat Anda mengetuk Izinkan di langkah Perizinan.
- Dash: warna peringatan (bensin, aki 12V, suhu mesin, baterai HP) sekarang mengikuti pengaturan di semua tempat, termasuk kartu layar Speedometer dan info pojok.
- Cadangan: cadangan otomatis juga tidak menyertakan daftar tempat Terakhir (Rumah, Kantor, dan favorit tetap ikut).

### Baru
- Tab Motor: "Jarak tempuh BBM" menjadi "Estimasi sisa jarak tempuh BBM (km)", dan angka perawatan memakai nama item terdekat (mis. "Sisa jarak Oli mesin (km)").
- Tema warna kini gradasi, dipakai di kartu besar aplikasi dan kotak data besar di dash.
- Pengaturan awal: langkah baru setelah layar selamat datang menanyakan nama panggilan (boleh dikosongkan).
- Navigasi: tombol "Cari SPBU terdekat".
- Pengaturan awal: bahasa langsung ditanyakan di tampilan pertama.
- Perizinan: izin Foto (galeri) ditambahkan. Tombol Selesai tidak bisa diketuk sebelum semua izin diberikan.
- Perawatan: tiap item bisa berdasarkan kilometer atau waktu. Item kilometer punya jarak "ingatkan sebelum" sendiri; item waktu (mis. masa berlaku SIM) punya tanggal jatuh tempo dan pengingat 1, 3, atau 6 bulan sebelumnya. Selang (1 bulan sampai 5 tahun) hanya bisa dipilih bila "Berulang" dinyalakan.
- Perawatan: ikon tiap item bisa dipilih dari banyak simbol dan emoji bertema motor.

### Diubah
- Tahun motor dihapus (pengaturan awal, Pengaturan, cadangan).
- Pengaturan > Peta: Rute dan pencarian dipindah ke bawah Peta offline.
- Kontrol stang: "Tekan 2x" menjadi "Tekan 2x cepat".
- Durasi klik cepat bawaan 300 ms; "Ingatkan sebelum servis" bawaan 100 km.
- Pengaturan format jam dihapus: selalu 24 jam.
- Perawatan: kelima item bawaan tidak bisa dihapus (hanya item tambahan yang bisa), dan namanya mengikuti bahasa app.
- Pengaturan sumber update dihapus: repo ditetapkan di dalam app (`AppConfig.updateRepo`).
- Eksperimen dan log: bagian Link CCU dan Bahasa dash disembunyikan.
- Tentang: keterangan di bawah "Versi dan update" dihapus.
- Pengaturan > Tampilan: kolom nama dipindah ke bawah Bahasa.
- Pengaturan > Motor dan BBM: jarak global "Ingatkan sebelum servis" dihapus (sekarang diatur per item).

## 0.1.2

### Baru
- Banner melayang saat ada versi baru, dan halaman "Yang baru di versi ini" di Pengaturan > Tentang.
- Perawatan: interval dan km terakhir diganti diketik, tanggal penggantian dicatat (bawaan hari ini), pengingat berupa
  notifikasi sistem dan banner melayang. Item ikut tercadangkan.
- Warna peringatan yang bisa diatur (jarak BBM, aki 12V, suhu mesin, baterai HP) di Kartu Data dash dan tab Motor.
- Perizinan: lokasi "Selalu", Bluetooth, musik, dan notifikasi diminta di pengaturan awal dan bisa dicek lagi di
  Pengaturan > Perizinan.
- Kode bahasa 11 kini dikirim ke dash untuk Indonesia.

### Diubah
- ODO hanya dibaca dari CCU dan tidak bisa diedit lagi.
- Pengaturan Rute dan pencarian pindah ke Pengaturan > Peta. Cadangkan dan pulihkan, serta Eksperimen dan log, pindah ke
  Pengaturan > Tentang.
- Nama jalan contoh di pratinjau peta dan tes suara adalah jalan terdekat di sekitar Anda.
- Sapaan tetap ("Hello" / "Halo"); hanya nama panggilan yang bisa diisi, dan kosong secara bawaan.
- Plat nomor dihapus. Tab Motor menampilkan nilai aki, suhu, dan kunci kontak secara langsung.
- Ikon motor baru. "Buka Google Maps" dan "Tempel tautan" lebih besar dan bold.
- Nama file cadangan bawaan menjadi `XConnect_setting.json`.

## 0.1.1

Rilis awal.

- Layar dash: Peta, Speedometer, Musik, dan Foto, dengan Kartu Data, panel navigasi, dan kontrol stang.
- Navigasi: pencarian, tautan Google Maps, tempat tersimpan, rute alternatif, simulasi, suara petunjuk arah, dan peta offline.
- Motor: ODO, aki, dan suhu dari CCU, perkiraan bensin, perawatan, dan riwayat perjalanan.
- English dan Bahasa Indonesia (kamus di `Translations.tsv`) serta tema warna plus gelap, terang, atau ikut ponsel.
- Pengaturan awal: sapaan, bahasa, dan motor.
- Cadangkan dan pulihkan, serta update dari GitHub Releases.
