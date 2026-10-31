#!/bin/zsh
# benchrun.sh TAG ENGINE "GAME DIR" EXE APPID "XENV" args... : one 120 s run with Metal HUD logging, then a summary line.
TAG=$1 ENG=$2 GD=$3 EXE=$4 APP=$5 XE=$6; shift 6
rm -f ~/$TAG.log
MAXSECS=${MAXSECS:-120} ENGINE=$ENG XENV="MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1 $XE" ~/gsession.sh $TAG "$GD" "$EXE" $APP "$@" >/dev/null 2>&1
sleep 20; g=""; c=""
while pgrep -f "gpu-guard.sh ~/$TAG.log" >/dev/null; do
  p=$(pgrep -if "^(.*[/\\\\])?${EXE}( |$)" | head -1)
  [ -n "$p" ] && { g="$g $(ioreg -r -d 1 -w0 -c AGXAccelerator | grep -oE '"Device Utilization %"=[0-9]+' | grep -oE '[0-9]+$')"; c="$c $(ps -o %cpu= -p $p | tr -d ' ')"; }
  sleep 10
done
fps=$(python3 -I ~/perf-hud-summary.py ~/$TAG.log --last 40 --min-frame-ms 1 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print('fps=%.1f frame_ms=%.2f gpu_ms=%.2f n=%s'%(d.get('fps',0),d.get('frame_ms',0),d.get('gpu_ms',0),d.get('samples','?')))" 2>/dev/null)
echo "$TAG: ${fps:-no-hud-data} | gpu%:$g | cpu%:$c | backend: $(grep -aoE 'DXVK: v[0-9.]+|D3DMetal|wined3d' ~/$TAG.log | sort -u | tr '\n' ' ') | crash: $(grep -aE '^crash report|no crash' ~/$TAG.log | tail -1)"
