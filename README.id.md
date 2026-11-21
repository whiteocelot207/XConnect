# XConnect

[English](README.md)

Aplikasi iPhone untuk menampilkan peta, data motor, musik, dan foto di dash TFT Yamaha NMAX / XMAX lewat
ExternalAccessory (iAP, `com.garmin.navilite.data`), plus data motor dari CCU lewat Bluetooth LE.
Tidak resmi dan tidak berafiliasi dengan Yamaha.

Versi sekarang: **0.1.1** (rilis pertama).

## Fitur

- **Layar dash**: Peta, Speedometer, Musik, Foto. Ganti dengan tombol stang; urutan dan layar awal bisa diatur.
  Pratinjau langsung di Home dan Pengaturan.
- **Kartu Data** di layar Peta: cuaca + sapaan, baterai HP, sisa bensin, jarak tempuh BBM, aki, ODO, suhu mesin/udara,
  kecepatan, RPM, jam, kunci kontak, kode gangguan, volume, jaringan, tanggal, arah, ketinggian, dan byte mentah CCU.
- **Navigasi**: cari tempat, tempel tautan Google Maps, simpan Rumah / Kantor / favorit, hingga 2 rute alternatif,
  pratinjau peta rute, simulasi navigasi, suara petunjuk arah (musik dikecilkan, ada penguat volume).
- **Routing** dengan Valhalla (profil skuter: jalan utama, batas kecepatan, tanjakan, gang, jalan setapak, feri, tol, terpendek).
- **Peta offline** dan gaya peta siang/malam (otomatis 18.00-06.00).
- **Tab Motor**: ODO, aki, cairan pendingin, perkiraan bensin, perawatan beserta riwayat, riwayat perjalanan.
- **Bensin**: konsumsi rata-rata dari dash (CCU) bila terbaca, lalu konsumsi Anda 30 hari terakhir, lalu nilai bawaan.
- **Kontrol stang**: zoom, ganti tampilan, gesture musik (volume, lagu berikutnya/sebelumnya, putar/jeda).
- **Cadangkan dan pulihkan** semua pengaturan, tempat, data motor, perawatan, bensin, dan perjalanan ke file JSON.
- **Update dari dalam app** lewat GitHub Releases (membuka SideStore, AltStore, atau LiveContainer).

## Bahasa dan tema

- **Bahasa** (Pengaturan > Tampilan): English (bawaan) dan Bahasa Indonesia. Berlaku untuk tampilan aplikasi, suara
  petunjuk arah, teks navigasi, teks yang digambar di dash, dan kode bahasa yang dikirim ke dash.
- **Tema warna** (Pengaturan > Tampilan): Samudra, Hutan, Senja, Mawar, Ungu, Merah tua, Hijau tosca, Grafit.
  Mode gelap/terang/ikut ponsel diatur terpisah.

### Kamus terjemahan

Semua teks ada di `Sources/Resources/Translations.tsv` (dipisah tab): kolom `key` (teks Inggris yang dipakai kode
sebagai `tr("...")`), lalu satu kolom per bahasa (sel kosong = teks Inggris). `{0}`, `{1}` adalah penampung nilai.
Baris berawalan `@` adalah data bahasa: `@name`, `@locale`, `@voice`, `@routing`, `@decimal`, `@dashLang`.
Menambah bahasa cukup menambah kolom. `@dashLang` hanya mengenal `0` = Inggris dan `15` = Vietnam; kode untuk
Indonesia belum diketahui sehingga kosong (tidak dikirim). Bisa dicoba manual di Pengaturan > Eksperimen dan log.

## Pasang

1. Bangun IPA (lihat di bawah) atau unduh `XConnect.ipa` dari [Releases](../../releases).
2. Pasang pertama kali dengan Sideloadly (atau SideStore / AltStore / LiveContainer). Bundle ID: `id.xconnect.app`.
3. Update berikutnya: Pengaturan > Tentang > Cek update sekarang. Tambahkan sumber update sekali.

Butuh iOS 15 ke atas. Izinkan lokasi "Selalu", Bluetooth, dan Media & Apple Music.

## Build tanpa Mac

1. Unggah seluruh isi folder ini (termasuk `.github`) ke repo GitHub **public**.
2. Settings > Actions > General > Workflow permissions: **Read and write**.
3. Actions > **iOS IPA** > Run workflow (juga jalan otomatis tiap push ke `main`).
4. Hasilnya ada di **Releases** (IPA dan `source.json`).

## Penomoran versi

Format `x.y.z`. `MARKETING_VERSION` di `project.yml` adalah versi dasar (`0.1.1`); tiap build menaikkan `z` otomatis
(0.1.1, 0.1.2, ...). Untuk minor baru, ubah jadi mis. `0.2.1` lalu push. Tag Release: `v<versi>`.

## Keterbatasan

- Belum diuji di motor: tekan tahan tombol stang di layar Musik, alat "Cari byte dari angka di dash", dan pratinjau peta rute.
- Letak byte konsumsi BBM rata-rata di data CCU belum diketahui; cari lewat Data mentah CCU.
- Dash tidak mengirim apa pun saat tombol ditahan, jadi tahan dikenali dari tekan berulang.
- iOS tidak punya API jumlah bar sinyal; ikon di dash memakai 4 bar bila ada data seluler.
- Ikon pesan di dash datang dari iOS (ANCS), bukan dari app.
- Belum ada traffic. Server demo Valhalla hanya untuk pemakaian wajar.
- Hanya lagu dari app Musik (Apple Music) yang bisa dibaca.
- Suara bahasa yang dipilih harus terpasang di iOS (Pengaturan > Aksesibilitas > Konten Terucap > Suara).

## Sumber data

Peta © OpenStreetMap contributors, tile OpenFreeMap (OpenMapTiles). Pencarian: Photon. SPBU: Overpass API.
Cuaca: Open-Meteo. Routing: Valhalla.
