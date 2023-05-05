#!/bin/bash
coderun_version="0.2.2"
echo "Generacion caddy $coderun_version"
file_name="/opt/caddy.conf/${nombre_dir}.conf"
cp $file_name ~/copia_caddy_${nombre_dir}.conf
    cat >$file_name <<CADDY
        redir $server_base_url $server_base_url/
        reverse_proxy $server_base_url/* localhost:$server_port {
            header_up x-coderun-version "$coderun_version"
            header_up x-Host {host}
            header_up X-immediate-IP {remote}
        }
CADDY
diff $file_name ~/copia_caddy_${nombre_dir}.conf