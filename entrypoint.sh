#!/bin/sh
config_file=/etc/nginx/conf.d/default.conf

touch $config_file 2>/dev/null
if [ $? = 0 ]; then
  echo Configuring nginx for bucket: $S3_BUCKET.
  cat > $config_file <<-EOF
  server {
    listen 443;
    server_name munki;

    ssl on;
    ssl_certificate $SSL_PATH/certs/$SSL_NAME.pem;
    ssl_certificate_key $SSL_PATH/private_keys/$SSL_NAME.pem;
    ssl_client_certificate $SSL_PATH/certs/ca.pam;
    ssl_crl $SSL_PATH/crl.pem;
    ssl_protocols TLSv1.2 TLSv1.1 TLSv1;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "EECDH+ECDSA+AESGCM EECDH+aRSA+AESGCM EECDH+ECDSA+SHA384 EECDH+ECDSA+SHA256 EECDH+aRSA+SHA384 EECDH+aRSA+SHA256 EECDH+aRSA+RC4 EECDH EDH+aRSA RC4 !aNULL !eNULL !LOW !3DES !MD5 !EXP !PSK !SRP !DSS";

    location ~ '^/repo/(.*)\$' {
      limit_except GET {
        deny all;
      }

      if (\$remote_addr = ${MIRROR_EXT:-0.0.0.0}) {
        return 301 ${MIRROR_INT:-http://0.0.0.0}/\$request_uri;
      }

      set \$key \$1;

      # Setup AWS Authorization header
      set \$aws_signature '';

      # the only reason we need lua is to get the current date
      set_by_lua \$now "return ngx.cookie_time(ngx.time())";

      # the access key
      set \$aws_access_key '$AWS_ACCESS_KEY';
      set \$aws_secret_key '$AWS_SECRET_KEY';

      # the actual string to be signed
      # see: http://docs.amazonwebservices.com/AmazonS3/latest/dev/RESTAuthentication.html
      set \$string_to_sign "\$request_method\n\n\n\nx-amz-date:\$now\n/$S3_BUCKET/\$key";

      # create the hmac signature
      set_hmac_sha1 \$aws_signature \$aws_secret_key \$string_to_sign;
      # encode the signature with base64
      set_encode_base64 \$aws_signature \$aws_signature;
      proxy_set_header x-amz-date \$now;
      proxy_set_header Authorization "AWS \$aws_access_key:\$aws_signature";

      # rewrite .* /\$key break;

      # we need to set the host header here in order to find the bucket
      proxy_set_header Host $S3_BUCKET.s3.amazonaws.com;
      rewrite .* /\$key break;

      proxy_pass https://$S3_BUCKET.s3-$S3_REGION.amazonaws.com;
    }
  }
EOF
else
  echo Could not write to $config_file. Manual configuration is expected.
fi

if [ -z "$1" ] || [ "${1:0:1}" = "-" ]; then
  set -- nginx $@
fi

exec dumb-init $@
