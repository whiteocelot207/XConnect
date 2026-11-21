# Catatan versi

Tambahkan bagian `## x.y.z` baru di paling atas untuk tiap rilis. Aplikasi hanya menampilkan bagian untuk versi yang
terpasang (Pengaturan > Tentang > Yang baru di versi ini); bila suatu versi tidak punya bagian sendiri, yang tampil adalah
bagian terbaru yang tidak lebih baru darinya. Bagian yang sama dipakai sebagai catatan rilis GitHub.

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
