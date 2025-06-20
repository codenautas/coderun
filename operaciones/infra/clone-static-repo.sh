git clone --filter=blob:none --no-checkout https://github.com/codenautas/coderun.git
cd coderun
git sparse-checkout init --cone
git sparse-checkout set operaciones
git checkout
