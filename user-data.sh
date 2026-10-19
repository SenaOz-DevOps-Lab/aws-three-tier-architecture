#!/bin/bash
# EC2 ilk acildiginda root olarak bir kez calisir.
# Ciktisi: /var/log/cloud-init-output.log

# --- 1) Paketler ---
# httpd: Apache web sunucusu
# php + php-mysqlnd: PHP ve MySQL surucusu
# mariadb105: terminalden RDS'i test etmek icin mysql istemcisi
dnf install -y httpd php php-mysqlnd mariadb105
systemctl enable --now httpd

# --- 2) DB bilgileri (deploy sirasinda doldurulur, repoya gercek deger yazilmaz) ---
DB_HOST="__DB_HOST__"
DB_USER="admin"
DB_PASS="__DB_PASS__"
DB_NAME="appdb"

# --- 3) Config dosyasi: web kokunun (/var/www/html) DISINDA, tarayicidan okunamaz ---
# <<EOF tirnaksiz: bash $DB_HOST gibi degiskenleri doldurur.
# \$db_host: "bunu degistirme, PHP degiskeni olarak aynen yaz".
cat > /var/www/config.php <<EOF
<?php
\$db_host = "$DB_HOST";
\$db_user = "$DB_USER";
\$db_pass = "$DB_PASS";
\$db_name = "$DB_NAME";
EOF
chown root:apache /var/www/config.php
chmod 640 /var/www/config.php

# --- 4) Health check sayfasi: ALB bunu kontrol eder (statik, DB'ye bagli degil) ---
echo "OK" > /var/www/html/health.html

# --- 5) Uygulama ---
# <<'EOF' tirnakli: icerik oldugu gibi yazilir, bash hicbir seyi degistirmez.
cat > /var/www/html/index.php <<'EOF'
<?php
mysqli_report(MYSQLI_REPORT_OFF);
require '/var/www/config.php';
$host = gethostname();
$ip   = $_SERVER['SERVER_ADDR'];
?>
<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<title>3-Tier Demo</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 720px; margin: 40px auto; padding: 0 16px; }
  .ok  { color: #1a7f37; } .err { color: #cf222e; }
  code { background: #f2f2f2; padding: 2px 6px; border-radius: 4px; }
</style>
</head>
<body>
<h1>AWS Three-Tier Demo</h1>
<p>Katmanlar: <b>ALB</b> &rarr; <b>EC2</b> &rarr; <b>RDS MySQL</b></p>
<p>Bu sayfayi sunan sunucu: <code><?= htmlspecialchars($host) ?></code> (<?= htmlspecialchars($ip) ?>)</p>
<?php
$conn = new mysqli($db_host, $db_user, $db_pass, $db_name);
if ($conn->connect_error) {
    echo "<p class='err'>DB baglanti HATASI: " . htmlspecialchars($conn->connect_error) . "</p></body></html>";
    exit;
}
echo "<p class='ok'>RDS baglantisi basarili (MySQL " . htmlspecialchars($conn->server_info) . ")</p>";

$conn->query("CREATE TABLE IF NOT EXISTS ziyaretler (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sunucu VARCHAR(100),
    zaman TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");

$stmt = $conn->prepare("INSERT INTO ziyaretler (sunucu) VALUES (?)");
$stmt->bind_param("s", $host);
$stmt->execute();

$toplam = $conn->query("SELECT COUNT(*) AS n FROM ziyaretler")->fetch_assoc()['n'];
echo "<p>Toplam ziyaret: <b>$toplam</b></p>";

$res = $conn->query("SELECT sunucu, zaman FROM ziyaretler ORDER BY id DESC LIMIT 10");
echo "<h3>Son 10 ziyaret</h3><ul>";
while ($row = $res->fetch_assoc()) {
    echo "<li>" . htmlspecialchars($row['zaman']) . " - " . htmlspecialchars($row['sunucu']) . "</li>";
}
echo "</ul>";
?>
</body>
</html>
EOF
