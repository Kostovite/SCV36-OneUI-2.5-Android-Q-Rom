#!/usr/bin/env bash
# Runs in WSL after port10_vndk.sh. For each system lib the S8 vendor needs: does the Android-10 donor have it,
# does the S8 Pie system have it? -> decides vndk-28 contents.
R=~/s8rom; W=$R/port10; G=$R/trees/g9600_root/system; cd $W
for abi in lib lib64; do
  : > both_$abi.txt; : > pieonly_$abi.txt; : > missing_$abi.txt
  while read l; do
    q=0; p=0
    [ -e $G/$abi/$l ] && q=1
    { [ -e s8sys/$abi/$l ] || [ -e s8sys/$abi/vndk-sp-28/$l ]; } && p=1
    if [ $q = 1 ] && [ $p = 1 ]; then echo $l >> both_$abi.txt
    elif [ $p = 1 ]; then echo $l >> pieonly_$abi.txt
    elif [ $q = 0 ]; then echo $l >> missing_$abi.txt; fi
  done < fromsys_$abi.txt
  echo "== $abi: in both=$(wc -l < both_$abi.txt)  only in S8 Pie=$(wc -l < pieonly_$abi.txt)  nowhere=$(wc -l < missing_$abi.txt)"
done
echo "-- lib64 only in S8 Pie:"; tr '\n' ' ' < pieonly_lib64.txt; echo
echo "-- lib64 nowhere:"; tr '\n' ' ' < missing_lib64.txt; echo
