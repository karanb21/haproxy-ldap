mkdir -p ldapproxy/ssl

cd ldapproxy/ssl
echo "Create CA key and certificate"
openssl genrsa -passout pass:passw0rd -aes256 -out myCA.key 4096
openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.pem -subj '/CN=root/O=ldaptest' -passin pass:passw0rd

echo "Create HAProxy key and certificate signing request"
openssl genrsa -passout pass:passw0rd -out ldapproxy.key 4096
openssl req -new -key ldapproxy.key -out ldapproxy.csr -subj '/CN=ldapproxy/O=ldaptest' -passin pass:passw0rd

echo "Sign HAProxy certificate using the self-signed CA OpenSSL can consume configuration files to specify certificate signing"

cat > ldapproxy.ext <<EOF
subjectAltName = @alt_names

[alt_names]
DNS.1 = walmart-bastion.internal.cloudapp.net
IP.1 = 10.1.0.4
EOF

openssl x509 -req -in ldapproxy.csr -CA myCA.pem -CAkey myCA.key -CAcreateserial -out ldapproxy.pem -days 30 -sha256 -extfile ldapproxy.ext -passin pass:passw0rd
cd ..

echo "preparing haproxy config"
mkdir config
mkdir private
mkdir certs
cat ssl/ldapproxy.pem ssl/myCA.pem ssl/ldapproxy.key > private/ldapproxy.bundle


cat > config/haproxy.cfg <<EOF
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
  bind                  *:1637 ssl crt $(pwd)/private/ldapproxy.bundle
  description           LDAPS Service
  option                tcpka
  default_backend       ldaps_service_back

backend ldaps_service_back
  server cp4ba-ldap-server 10.1.2.4:389 check
  mode                  tcp
  balance               leastconn
EOF

echo "running haproxy as a daemon on port 1637"
haproxy -D -f /datadrive/ldapproxy/config/haproxy.cfg
