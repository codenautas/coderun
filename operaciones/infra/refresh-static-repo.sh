export NVM_DIR="/opt/.nvm"
cd $NVM_DIR
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
cd /opt/static/coderun
git pull
cd operaciones
npm ci
npm run deploy