#!/bin/bash
export NVM_DIR="/opt/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
if [ -z ${1+x} ]; then echo "last node"; else nvm use $1; fi
npm start
