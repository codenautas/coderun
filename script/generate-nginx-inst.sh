#!/bin/bash
coderun_version="0.2.4"
echo "Generacion nginx $coderun_version"
file_name="/opt/nginx.conf/${nombre_dir}.conf"
cp $file_name ~/copia_${nombre_dir}.conf
    cat >$file_name <<NGINX
        location $server_base_url {
            proxy_pass http://localhost:${server_port}${server_base_url};
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header x-Host \$host;
            proxy_set_header x-inmediate-IP \$remote_addr;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-coderun-version '$coderun_version';
            proxy_cache_bypass \$http_upgrade;
        }
NGINX
diff $file_name ~/copia_${nombre_dir}.conf