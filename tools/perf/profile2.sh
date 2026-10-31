#!/bin/zsh
# profile2.sh TAG ENGINE "GAME DIR" EXE APPID "XENV" args... : at t=60 s, per-thread CPU (thcpu) + stacks (sample) over the same 10 s.
TAG=$1 ENG=$2 GD=$3 EXE=$4 APP=$5 XE=$6; shift 6
O=~/cpuprof/$TAG; mkdir -p $O
MAXSECS=100 ENGINE=$ENG XENV="$XE" ~/gsession.sh $TAG "$GD" "$EXE" $APP "$@" >/dev/null 2>&1
for i in $(seq 1 60); do p=$(pgrep -if "^(.*[/\\\\])?${EXE}( |$)" | head -1); [ -n "$p" ] && break; sleep 2; done
sleep 55
~/nectarine-runtime/thcpu $p 10 | sort -rn > $O/thcpu.txt & sample $p 10 1 -file $O/sample.txt >/dev/null 2>&1; wait
echo "== thread CPU (10 s)"; head -8 $O/thcpu.txt
ids=$(head -4 $O/thcpu.txt | grep -oE "Thread_[0-9]+" | sed 's/Thread_//' | tr '\n' ',' | sed 's/,$//')
python3 -I /tmp/threadtop.py $O/sample.txt 4 "$ids"
