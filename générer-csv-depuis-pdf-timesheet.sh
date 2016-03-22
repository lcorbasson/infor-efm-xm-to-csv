#!/bin/bash
check_prerequisites() { #VERSION: 0.0.0:
	for command in \
		awk \
		cat \
		date \
		grep \
		head \
		iconv \
		mkdir \
		parallel \
		rm \
		sed \
		sort \
		tr \
		; do
		if [ -z "$(which "$command")" ]; then
			echo "$command is required; aborting." >&2
			exit 254
		fi
	done
}
check_prerequisites #END check_prerequisites

ROOTDIR="$(realpath "$(dirname "$0")")"
DATADIR="$ROOTDIR/data"
TSDIR="$ROOTDIR/timesheets"
TMPDIR="$ROOTDIR/temp"
RUN="$(date -Iseconds)"
RUN="${RUN//:/}"
RUN="${RUN//+/}"
RUN="${RUN//-/}"
WEEKLYFILE="$DATADIR/weekly.csv"
DAILYFILE="$DATADIR/daily.csv"
DAILYSUMFILE="$DATADIR/dailysum.csv"

declare -A MONTHS=([janv]=1 [févr]=2 [mars]=3 [avr]=4 [mai]=5 [juin]=6 [juil]=7 [août]=8 [sept]=9 [oct]=10 [nov]=11 [déc]=12)

exec 4>&2

timetype() {
  code="${1%%	*}"
  billable="${1##*	}"
  case "$code" in
    6200100000*) # Congé payé
      echo -n "p"
      ;;
    6200200000*) # RTT payée (Q1)
      echo -n "r"
      ;;
    6200210000*) # RTT non payée (Q2)
      echo -n "r"
      ;;
    6200330000*) # Congé enfant malade
      echo -n "e"
      ;;
    6200340000*) # Congé événement familial
      echo -n "n"
      ;;
    6400200000*) # Congé maternité
      echo -n "m"
      ;;
    6200400000*) # Congé paternité
      echo -n "m"
      ;;
    6200600000*) # Congé déménagement
      echo -n "v"
      ;;
    6200300000*) # Congé exceptionnel
      echo -n "y"
      ;;
    6400100000*) # Arrêt maladie
      echo -n "a"
      ;;
    6600000000*) # Commerce
      echo -n "b"
      ;;
    6000000000*) # Intercontrat
      echo -n "o"
      ;;
    6800000000*) # Administration
      echo -n "k"
      ;;
    7200100000*) # Formation de base
      echo -n "f"
      ;;
    7200110000*) # Formation
      echo -n "f"
      ;;
    *)
      case "$billable" in
        Non*) # Non facturable
          echo -n "v"
          ;;
        *)
          echo -n "w"
          ;;
      esac
      ;;
  esac
}
export -f timetype

checkcols() {
  local file="$1"
  shift
  shift
  ! sed -e '/^'"$(printf '[^\\t]*\\t%.0s' "$@")"'[^\t]*$/d' "$file" | grep '.' >&2
}
export -f checkcols

monthlytoweeklyfile() {
  local monthly="$1"
  # for each week
  weekstarts=(18 $(grep -n '^lun\.$' "$monthly" | cut -d: -f1) )
  head -17 "$monthly"
  # TODO
}

timesheetname() {
  local f="$(head -1 "$1")"
  local tsref="$(sed -n -e '5{s,^[^A-Z0-9]*\(TS[0-9][0-9]*\)[^A-Z0-9].*$,\1,g;p}' "$1" | tr -d '\n')"
  f="${f// / }"
  f="${f//­/-}"
  f="${f//|/_}"
  f="${f##* Récapitulatif du projet dans la feuille de présence }"
  local timesheet="${f% _ *}"
  local dates="${f##* _ }"
  local date1="${dates% - *}"
  local date2="${dates#* - }"
#  date1="$(echo "$date1" | iconv -f utf-8 -t ascii --unicode-subst='_u%04X_')"
#  date2="$(echo "$date2" | iconv -f utf-8 -t ascii --unicode-subst='_u%04X_')"
  local d1
  local d2
  IFS=' ' read -a d1 <<< "$date1"
  IFS=' ' read -a d2 <<< "$date2"
  local beginning="${d1[2]}-$(printf "%02d" "${MONTHS[${d1[1]%.}]}")-$(printf "%02d" "${d1[0]}")"
  [ -z "${d2[2]}" ] && d2[2]="${d1[2]}"
  [ $((${beginning//-/}%10000)) -ge 1226 ] && d2[2]=$((${d1[2]}+1))
  local end="${d2[2]}-$(printf "%02d" "${MONTHS[${d2[1]%.}]}")-$(printf "%02d" "${d2[0]}")"
  echo "$RUN _ $timesheet _ $beginning _ $end _ $tsref"
}
export -f timesheetname

tstotxt() {
  local desc="PDF timesheets --> TXT files"
#  echo "$desc" >&4
  echo "1/3 $desc" >&2
  parallel --bar --will-cite pdftotext -raw "{}" ::: *.pdf
  for f in *.txt; do
    movets "$f"
  done
}
export -f tstotxt

movets(){
  mv "$1" "$TMPDIR/$(timesheetname "$1").txt"
}
export -f movets

txttoweeklycsv() {
  local desc="TXT files --> Weekly CSV"
#  echo "$desc" >&4
  local f="$1"
#  echo "Début de semaine	Fin de semaine	Code projet	Projet	Type	Lu	Ma	Me	Je	Ve	Sa	Di	Total"
  lines="$(($(grep -n '^Total $' "$f" | cut -f1 -d:)+1))$(grep -n '\.00 $' "$f" | while IFS=':' read n l; do echo -n " $(($n+1))"; done)"
  read -a lines <<< "$lines"
  unset lines[${#lines[@]}-1]
  i=1
  while [ $i -lt ${#lines[@]} ]; do
    echo -n "$f" \
      | sed -e 's,.* _ \([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\) _ \([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\) _ .*,\1\t\2\t,g'
    sed -n -e "${lines[$i-1]},$((${lines[$i]}-1))"'p' "$f" | tr '\n' '\t' \
      | iconv -f utf-8 -t ascii//translit \
      | tr -d "'^\`" \
      | sed \
      -e 's,­,-,g' \
	-e 's, , ,g' \
      -e 's,-\t,-,g' \
      -e 's,\t, ,g' \
      -e 's,^\([A-Z0-9][A-Z0-9_-]*\)  *\(.*\)  *\(Facturable  *[A-Z][A-Z ]*[A-Z]  \|Non facturable    \|Non facturable  [A-Z][A-Z ]*[A-Z]  \)  \([0-9.-]*\)  \([0-9.-]*\)  \([0-9.-]*\)  \([0-9.-]*\)  \([0-9.-]*\)  *[0-9.-][0-9.-]*  *\([0-9.-][0-9.-]*\) *$,\1\t\2\t\3\t\4\t\5\t\6\t\7\t\8\t0.00\t0.00\t\9\t,g' \
      -e 's,\.00,,g' \
      -e 's,\t\t,\t0\t,g' \
      -e 's,\t\t,\t0\t,g' \
      -e 's,\t\([0-9]\)\t,\t  \1\t,g' \
      -e 's,\t\([0-9]\)\t,\t  \1\t,g' \
      -e 's,\t\([0-9-][0-9]\)\t,\t \1\t,g' \
      -e 's,\t\([0-9-][0-9]\)\t,\t \1\t,g' \
      -e 's,\t$,\n,g'
    i=$(($i+1))
  done | sort \
    | awk 'BEGIN{ FS="\t"; OFS=FS; } { printf "%s\t%s\t%-23s\t%-31s\t%-39s\t", $1, $2, $3, $4, $5; print $6, $7, $8, $9, $10, $11, $12, $13; }'
}
export -f txttoweeklycsv

weeklycsvtodailycsv() {
  local desc="Weekly CSV --> Daily CSV"
#  echo "$desc" >&4
#  echo "Jour	Code projet	Projet	Type	Charge"
#  sed -e '1d' | \
  while IFS=$'\t' read d1 d2 code projet type lu ma me je ve sa di total; do
    (
      date -Idate -d"$d1 + 0 day"
      echo "$code"
      echo "$projet"
      echo "$type"
    ) | tr '\n' '\t'
      echo "$lu"
    (
      date -Idate -d"$d1 + 1 day"
      echo "$code"
      echo "$projet"
      echo "$type"
    ) | tr '\n' '\t'
      echo "$ma"
    (
      date -Idate -d"$d1 + 2 day"
      echo "$code"
      echo "$projet"
      echo "$type"
    ) | tr '\n' '\t'
      echo "$me"
    (
      date -Idate -d"$d1 + 3 day"
      echo "$code"
      echo "$projet"
      echo "$type"
    ) | tr '\n' '\t'
      echo "$je"
    (
      date -Idate -d"$d1 + 4 day"
      echo "$code"
      echo "$projet"
      echo "$type"
    ) | tr '\n' '\t'
      echo "$ve"
    (
      date -Idate -d"$d1 + 5 day"
      echo "$code"
      echo "$projet"
      echo "$type"
    ) | tr '\n' '\t'
      echo "$sa"
    (
      date -Idate -d"$d1 + 6 day"
      echo "$code"
      echo "$projet"
      echo "$type"
    ) | tr '\n' '\t'
      echo "$di"
  done | sort
}
export -f weeklycsvtodailycsv

txttodailycsv() {
  local f="$1"
  txttoweeklycsv "$f" | weeklycsvtodailycsv > "$f.daily.csv"
}
export -f txttodailycsv

alltxttodailysumcsv() {
  #parallel --will-cite --linebuffer txttodailycsv ::: "$RUN _ "*.txt ::: "$header" 4>&2 >> "$DAILYSUMFILE"
  #parallel --will-cite txttodailycsv ::: "$RUN _ "*.txt 4>&2
  local desc="TXT files --> Daily CSV"
  echo "2/3 $desc" >&2
  parallel --bar --will-cite 'txttodailycsv {} 4>&2' ::: "$RUN _ "*.txt
  local desc="Daily CSV --> Daily sum CSV"
  echo "3/3 $desc" >&2
  echo "Créneau	Date	Activité	Code projet	Projet	Type" > "$DAILYSUMFILE"
  parallel --bar --will-cite 'RUN="'"$RUN"'" dailycsvstodailysumcsv {} 4>&2' ::: "$RUN _ 1 - "*".daily.csv"
  cat "$RUN _ "*".dailysum.csv" >> "$DAILYSUMFILE"
}
export -f alltxttodailysumcsv

dailycsvstodailysumcsv() {
  local d="$1"
  d="${d#* _ }"
  d="${d% _ TS*}"
  sort "$RUN _ "*"$d _ TS"*".daily.csv" > "$RUN _ $d.allentries.csv"
  dailycsvtodailysumcsv "$RUN _ $d.allentries.csv" > "$RUN _ $d.dailysum.csv"
}
export -f dailycsvstodailysumcsv

dailycsvtodailysumcsv() {
  local desc="Daily CSV --> Daily sum CSV"
#  echo "$desc" >&4
  local f="$1"
  projects="$(cut -d'	' -f2-4 "$f" | sort -u)"
  firstdate="$(head -1 "$f" | cut -d'	' -f1)"
  firstdate="${firstdate//-/}"
  lastdate="$(tail -1 "$f" | cut -d'	' -f1)"
  lastdate="${lastdate//-/}"
  i="$firstdate"
  xx="00"
  declare -A daypartA
  declare -A daypartB
#  echo "Créneau	Date	Activité	Code projet	Projet	Type"
  while [ $i -le $lastdate ]; do
    y=$(($i/10000))
    m=$((($i%10000)/100))
    d=$(($i%100))
    ymd="$y-${xx:${#m}}$m-${xx:${#d}}$d"
    lines="$(sed -n -e "$(grep -n "^$ymd	" "$f" | sed -n -e 's,^\([0-9]*\):.*,\1,g;1p;$p' | tr '\n' ',' | sed -e 's,.$,{/\t0$/d;p},g')" "$f")"
    while IFS='' read -r project; do
      sum=$(($(grep -e "^$ymd	$project	" <<< "$lines" | cut -d'	' -f5 | tr '\n' '+')0))
      case $sum in
        0)
          ;;
        5)
          if [ -z "${daypartA[$i]}" ]; then
            daypartA[$i]="$project"
          else
            daypartB[$i]="$project"
          fi
        ;;
        10)
          daypartA[$i]="$project"
          daypartB[$i]="$project"
        ;;
        *)
          echo "Erreur : $ymd : somme des charges : $sum !" >&2
          echo "$lines" | sed -e 's,^,\t,g' >&2
      esac
    done <<< "$projects"
    if [ -n "${daypartA[$i]}" ]; then
      echo "$ymd-A	$ymd	$(timetype "${daypartA[$i]}")	${daypartA[$i]}"
      echo "$ymd-B	$ymd	$(timetype "${daypartB[$i]}")	${daypartB[$i]}"
    fi
    i=$(($i+1))
    [ $d -gt 31 ] && i=$(($i-($i%100)+101))
    [ $m -gt 12 ] && i=$(($i-($i%10000)+10101))
  done
}
export -f dailycsvtodailysumcsv

mkdir -p "$TMPDIR" "$DATADIR"

pushd "$TMPDIR" > /dev/null && rm -f *.txt
popd > /dev/null

pushd "$DATADIR" > /dev/null

pushd "$TSDIR" > /dev/null || ( echo "Timesheet directory $TSDIR not found!" >&2 && exit 1 )
tstotxt || exit 2
popd > /dev/null

pushd "$TMPDIR" > /dev/null
#txttoweekly || exit 3
alltxttodailysumcsv
#  checkcols "$WEEKLYFILE" {1..13} || ( echo "$desc failed!" >&2 && false )
popd > /dev/null

pushd "$DATADIR" > /dev/null
#weeklytodaily || exit 4
#  checkcols "$DAILYFILE" {1..5} || ( echo "$desc failed!" >&2 && false )
#dailytodailysum || exit 5
#  checkcols "$DAILYSUMFILE" {1..6} || ( echo "$desc failed!" >&2 && false )
popd > /dev/null

pushd "$TMPDIR"
rm -f "$RUN _ "*.txt
popd > /dev/null

popd > /dev/null

