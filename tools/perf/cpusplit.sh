#!/bin/zsh
# cpusplit.sh TAG ENGINE "GAME DIR" EXE APPID "XENV" args... : per-process and per-thread CPU over 10 s at t=60 s.
TAG=$1 ENG=$2 GD=$3 EXE=$4 APP=$5 XE=$6; shift 6
MAXSECS=100 ENGINE=$ENG XENV="$XE" ~/gsession.sh $TAG "$GD" "$EXE" $APP "$@" >/dev/null 2>&1
for i in $(seq 1 60); do p=$(pgrep -if "^(.*[/\\\\])?${EXE}( |$)" | head -1); [ -n "$p" ] && break; sleep 2; done
sleep 55
tsec() { ps -M -p $p | awk 'NR>1{u=$(NF-1); s=$(NF-2); split(u,a,":"); split(s,b,":"); print NR, (a[1]*60+a[2]) + (b[1]*60+b[2])}'; }
psec() { ps -Ao pid=,time=,comm= | awk '{split($2,a,":"); t=0; n=split($2,x,":"); if(n==3)t=x[1]*3600+x[2]*60+x[3]; else t=x[1]*60+x[2]; $2=""; print $1, t, $0}'; }
tsec > /tmp/t1; psec > /tmp/p1; sleep 10; tsec > /tmp/t2; psec > /tmp/p2
echo "== processes (CPU-seconds in 10 s, >0.3)"
join <(sort /tmp/p1 | awk '{print $1, $2}') <(sort /tmp/p2) | awk '{d=$3-$2; if (d>0.3) {c=""; for(i=4;i<=NF;i++) c=c" "$i; printf "%6.2f %s\n", d, c}}' | sort -rn | head -12
echo "== game threads (CPU-seconds in 10 s, >0.05)"
join /tmp/t1 /tmp/t2 | awk '{d=$3-$2; if (d>0.05) printf "%6.2f thread#%s\n", d, $1}' | sort -rn | head -14
