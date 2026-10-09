#!/usr/bin/env bash
# Run in WSL: smali/baksmali 2.5.2 (vdexExtractor is built separately in ~/s8rom/tools_bin, -Werror removed).
set -e
T=~/s8rom/tools_bin; mkdir -p $T; cd $T
rm -f .jar
for j in smali baksmali; do
  if ! unzip -tq $j.jar >/dev/null 2>&1; then
    curl -sL -o $j.jar "https://bitbucket.org/JesusFreke/smali/downloads/$j-2.5.2.jar"
    unzip -tq $j.jar >/dev/null 2>&1 || curl -sL -o $j.jar "https://github.com/JesusFreke/smali/releases/download/v2.5.2/$j-2.5.2.jar" || true
  fi
  printf '%-14s ' $j.jar; unzip -tq $j.jar >/dev/null 2>&1 && echo "OK ($(stat -c %s $j.jar) bytes)" || echo "BAD"
done
java -jar baksmali.jar --version 2>&1 | head -1
./vdexExtractor 2>&1 | grep -m1 -i 'vdexExtractor'
