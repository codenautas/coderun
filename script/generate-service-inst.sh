#!/bin/bash
coderun_version="0.1.7"
echo "Generacion servicio $coderun_version"
file_name="/opt/services/${nombre_dir}.service"
cp $file_name ~/copia_${nombre_dir}.service
    cat >$file_name <<SERVICE
[Unit]
Description=$nombre_dir - node
[Service]
ExecStart=/opt/bin/coderun/script/run-app.sh
Restart=always
RestartSec=5
WorkingDirectory=/opt/npm/$nombre_dir
User=$server_user
Group=runner
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=$nombre_dir
[Install]
WantedBy=multi-user.target
SERVICE
diff $file_name ~/copia_${nombre_dir}.service