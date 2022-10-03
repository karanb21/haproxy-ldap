#for ubuntu18
apt install haproxy openjdk-8-jre-headless ldap-utils openssl -y

cat > /etc/ssl/openssl.cnf <<EOF
[ req ]
#default_bits   = 2048
#default_md   = sha256
#default_keyfile  = privkey.pem
distinguished_name  = req_distinguished_name
attributes    = req_attributes

[ req_distinguished_name ]

[ req_attributes ]
challengePassword   = A challenge password
challengePassword_min   = 4
challengePassword_max   = 20
EOF

export OPENSSL_CONF=/etc/ssl/openssl.cnf

mkdir -p haproxy/ssl

cd haproxy/ssl
#docker rm -f hap
echo "generating CA and proxy cert"
openssl genrsa -passout pass:passw0rd -aes256 -out myCA.key 4096
openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.pem -subj '/CN=root/O=ldaptest' -passin pass:passw0rd
openssl genrsa -passout pass:passw0rd -out ldapproxy.key 4096
openssl req -new -key ldapproxy.key -out ldapproxy.csr -subj '/CN=ldapproxy/O=ldaptest' -passin pass:passw0rd

cat > ldapproxy.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = comfy1.fyre.ibm.com
DNS.2 = ldapproxy.ibm.com

EOF
openssl x509 -req -in ldapproxy.csr -CA myCA.pem -CAkey myCA.key -CAcreateserial -out ldapproxy.pem -days 30 -sha256 -extfile ldapproxy.ext -passin pass:passw0rd
cd ..

echo "preparing haproxy config"
mkdir config
mkdir private
mkdir certs
cat ssl/ldapproxy.pem ssl/myCA.pem ssl/ldapproxy.key > private/ldapproxy.bundle
echo "getting target ldap cert(s)"
keytool -printcert -sslserver bluepages.ibm.com:636 -rfc > certs/bluepages.pem


cat > config/haproxy.cfg <<EOF
global
  user       haproxy
  group      haproxy

defaults
  timeout http-request    10s
  timeout queue           1m
  timeout connect         10s
  timeout client          1m
  timeout server          1m
  timeout http-keep-alive 10s
  timeout check           10s
  maxconn                 3000

frontend ldaps_service_front
  mode                  tcp
  bind                  *:1636 ssl crt $(pwd)/private/ldapproxy.bundle
  description           LDAPS Service
  option                tcpka
  default_backend       ldaps_service_back

backend ldaps_service_back
  server                ldap1 bluepages.ibm.com:636 ssl ca-file $(pwd)/certs/bluepages.pem
  mode                  tcp
  balance               leastconn
  option                ldap-check
  timeout server        10s
  timeout connect       1s

EOF

echo "running the proxy"
#docker run -itd --name hap -v $(pwd)/private:/etc/ssl/private -v $(pwd)/config:/usr/local/etc/haproxy:ro -v $(pwd)/certs:/etc/ssl/certs -p 1636:1636 haproxy
#if running haproxy from container make sure ldap servers can be resolved inside the container
#running haproxy as daemon on the system
haproxy -D -f ./config/haproxy.cfg

echo "testing"
export LDAPTLS_CACERT=$(pwd)/ssl/myCA.pem
ldapsearch -x  -H ldaps://comfy1.fyre.ibm.com:1636 -b ou=bluepages,o=ibm.com 'mail=karanb@ibm.com' cn
openssl s_client -showcerts -connect comfy1.fyre.ibm.com:1636 </dev/null
