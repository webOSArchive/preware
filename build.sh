#!/bin/bash
APPID=org.webosinternals.preware
mkdir -p ./bin
# Signing files are optional: builds without them install and run fine on webOS
KEYS=1
for key in cert.pem pubkey.pem signature.sha1; do
    [ ! -f keys/$key ] && KEYS=0
done

useBin=arm
for arg in "$@"; do
    if [ "$arg" = 'i686' ]; then
        useBin=i686
    fi
done

echo "building preware for $useBin..."
rm ./source/bin/org.webosinternals.ipkgservice >/dev/null 2>&1
cp ./source/bin/org.webosinternals.ipkgservice.$useBin ./source/bin/org.webosinternals.ipkgservice

# Bundle everything into a palm package
palm-package source/. -o ./bin --exclude=*.arm --exclude=*.i686
# Find what was just made
unset -v ipk
for file in "./bin"/*.ipk; do
    [[ $file -nt $ipk ]] && ipk=$file
done
if [ -z "${ipk:-}" ]; then 
    echo "build failed, palm-package did not produce a deployable ipk"
    exit
fi

# Inject extra files
echo "adding install files..."
ar qv $ipk source/pmPostInstall.script
ar qv $ipk source/pmPreRemove.script
if [ "$KEYS" -eq "1" ]; then
    ar qv $ipk keys/cert.pem
    ar qv $ipk keys/pubkey.pem
    ar qv $ipk keys/signature.sha1
else
    echo "signing files not found in keys/, leaving them out"
fi
mv $ipk ${ipk%_all.ipk}_$useBin.ipk
for file in "./bin"/*.ipk; do
    [[ $file -nt $ipk ]] && ipk=$file
done
echo
echo "output ready at $ipk"

